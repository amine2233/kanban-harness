import ArgumentParser
import DashboardAI
import DashboardDomain
import DashboardRuntime
import DashboardService
import Foundation

struct AICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai",
        abstract: "AI assistant configuration (providers live in config.json / config.yaml).",
        subcommands: [Providers.self, Ticket.self]
    )

    struct Providers: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "providers",
            abstract: "List, add, remove AI providers and pick the default.",
            subcommands: [List.self, Add.self, Remove.self, Default.self]
        )

        /// Printable view: never shows the key itself.
        struct View: Encodable {
            let defaultProvider: String?
            let providers: [ProviderView]

            enum CodingKeys: String, CodingKey {
                case providers
                case defaultProvider = "default_provider"
            }

            init(_ config: AIConfig) {
                defaultProvider = config.defaultProviderId
                providers = config.providers.map(ProviderView.init)
            }
        }

        struct ProviderView: Encodable {
            let id: String
            let kind: AIProviderKind
            let name: String
            let model: String
            let baseURL: String?
            let maxTokens: Int?
            let hasAPIKey: Bool

            enum CodingKeys: String, CodingKey {
                case id, kind, name, model
                case baseURL = "base_url"
                case maxTokens = "max_tokens"
                case hasAPIKey = "has_api_key"
            }

            init(_ p: AIProviderConfig) {
                id = p.id
                kind = p.kind
                name = p.name
                model = p.model
                baseURL = p.baseURL
                maxTokens = p.maxTokens
                hasAPIKey = p.hasAPIKey
            }
        }

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show configured providers (keys are never printed).")
            @OptionGroup var global: GlobalOptions

            func run() async throws {
                try await failing {
                    try Output.json(View(try await Runtime.run(global) { try await $0.make(AIConfigCommandsKey.self).current() }))
                }
            }
        }

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Add or replace a provider.")
            @OptionGroup var global: GlobalOptions

            @Argument(help: "Provider id (a-z, 0-9, _), e.g. claude, local.")
            var id: String

            @Option(help: "anthropic, openai_compatible or ollama.")
            var kind: AIProviderKind

            @Option(help: "Model name, e.g. claude-sonnet-5, gpt-4o, llama3.2.")
            var model: String

            @Option(help: "Display name (defaults to the id).")
            var name: String?

            @Option(name: .customLong("base-url"), help: "API base URL (required for openai_compatible and ollama unless the vendor default applies).")
            var baseURL: String?

            @Option(name: .customLong("api-key"), help: "API key; prefer the env var MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY to keep it out of the file.")
            var apiKey: String?

            @Option(name: .customLong("max-tokens"), help: "Response token limit.")
            var maxTokens: Int?

            func run() async throws {
                try await failing {
                    let provider = try AIProviderConfig(
                        id: id, kind: kind, name: name ?? id, model: model, baseURL: baseURL, apiKey: apiKey, maxTokens: maxTokens
                    )
                    try Output.json(View(try await Runtime.run(global) { try await $0.make(AIConfigCommandsKey.self).upsert(provider) }))
                }
            }
        }

        struct Remove: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Remove a provider.")
            @OptionGroup var global: GlobalOptions
            @Argument var id: String

            func run() async throws {
                try await failing {
                    try Output.json(View(try await Runtime.run(global) { try await $0.make(AIConfigCommandsKey.self).remove(id) }))
                }
            }
        }

        struct Default: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Make a provider the default.")
            @OptionGroup var global: GlobalOptions
            @Argument var id: String

            func run() async throws {
                try await failing {
                    try Output.json(View(try await Runtime.run(global) { try await $0.make(AIConfigCommandsKey.self).setDefault(id) }))
                }
            }
        }
    }
}

extension AICommand {
    struct Ticket: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ticket",
            abstract: "Draft a ticket from an idea with the configured AI provider; --create turns it into a card."
        )

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or id.")
        var project: String

        @Argument(help: "The idea, in a sentence or two.")
        var idea: String

        @Option(help: "Board name or id (default: the project's first board).")
        var board: String?

        @Option(help: "Provider id (default: the configured default provider).")
        var provider: String?

        @Option(help: "Column name or id for --create (default: the board's first column).")
        var column: String?

        @Flag(help: "Create the card right away instead of only printing the draft.")
        var create = false

        func run() async throws {
            try await failing {
                try await Runtime.run(global) { services in
                    let boards = services.make(BoardCommandsKey.self)
                    let ref = ProjectRef.parse(project)
                    let all = try await boards.boards(ref)
                    guard let target = board.map({ b in all.first { $0.name.caseInsensitiveCompare(b) == .orderedSame || $0.id.uuidString.caseInsensitiveCompare(b) == .orderedSame } }) ?? all.first else {
                        throw ServiceError.domain(.notFound(board ?? "board"))
                    }
                    let drafted = try await services.make(AssistantCommandsKey.self)
                        .draftTicket(project: ref, boardId: target.id, idea: idea, providerId: provider)
                    if create {
                        let columns = try await boards.columns(ref, boardId: target.id)
                        guard let destination = column.map({ c in columns.first { $0.name.caseInsensitiveCompare(c) == .orderedSame || $0.id.uuidString.caseInsensitiveCompare(c) == .orderedSame } }) ?? columns.first else {
                            throw ServiceError.domain(.notFound(column ?? "column"))
                        }
                        let card = try await boards.createCard(ref, columnId: destination.id, title: drafted.draft.title, description: drafted.draft.cardDescription, priority: drafted.draft.priority)
                        try Output.json(CreatedView(draft: drafted, card: card))
                    } else {
                        try Output.json(DraftView(drafted))
                    }
                }
            }
        }

        struct DraftView: Encodable {
            let draft: TicketDraft
            let provider: String
            let model: String
            let costUSD: Double?
            enum CodingKeys: String, CodingKey { case draft, provider, model; case costUSD = "cost_usd" }
            init(_ d: DraftedTicket) { draft = d.draft; provider = d.providerId; model = d.model; costUSD = d.usage.costUSD }
        }

        struct CreatedView: Encodable {
            let draft: DraftView
            let cardId: String
            let key: String
            enum CodingKeys: String, CodingKey { case draft, key; case cardId = "card_id" }
            init(draft: DraftedTicket, card: Card) { self.draft = DraftView(draft); cardId = card.id.uuidString.lowercased(); key = "\(card.prefix)-\(card.cardNumber)" }
        }
    }
}

extension AIProviderKind: ExpressibleByArgument {}
