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
            subcommands: [List.self, Add.self, Remove.self, Default.self, Login.self, Logout.self]
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
                self.defaultProvider = config.defaultProviderId
                self.providers = config.providers.map(ProviderView.init)
            }
        }

        struct ProviderView: Encodable {
            let id: String
            let kind: AIProviderKind
            let name: String
            let model: String
            let baseURL: String?
            let maxTokens: Int?
            let pricing: AIPricing?
            let hasAPIKey: Bool

            enum CodingKeys: String, CodingKey {
                case id
                case kind
                case name
                case model
                case pricing
                case baseURL = "base_url"
                case maxTokens = "max_tokens"
                case hasAPIKey = "has_api_key"
            }

            init(_ p: AIProviderConfig) {
                self.id = p.id
                self.kind = p.kind
                self.name = p.name
                self.model = p.model
                self.baseURL = p.baseURL
                self.maxTokens = p.maxTokens
                self.pricing = p.pricing
                self.hasAPIKey = p.hasAPIKey
            }
        }

        struct List: AsyncParsableCommand {
            static let configuration =
                CommandConfiguration(abstract: "Show configured providers (keys are never printed).")
            @OptionGroup var global: GlobalOptions

            func run() async throws {
                try await failing {
                    try await Output
                        .json(View(Runtime
                                .run(global) { try await $0.make(AIConfigCommandsKey.self).current() }))
                }
            }
        }

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Add or replace a provider.")
            @OptionGroup var global: GlobalOptions

            @Argument(help: "Provider id (a-z, 0-9, _), e.g. claude, local.")
            var id: String

            @Option(help: "apple, anthropic, openai, gemini, ollama, huggingface, openrouter or claude_code.")
            var kind: AIProviderKind

            @Option(help: "Model name, e.g. claude-sonnet-5, gpt-4o, llama3.2.")
            var model: String

            @Option(help: "Display name (defaults to the id).")
            var name: String?

            @Option(
                name: .customLong("base-url"),
                help: "API base URL; defaults to the vendor endpoint (OpenAI-compatible servers: their /v1 URL)."
            )
            var baseURL: String?

            @Option(
                name: .customLong("api-key"),
                help: "API key; prefer the env var MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY to keep it out of the file."
            )
            var apiKey: String?

            @Option(name: .customLong("max-tokens"), help: "Response token limit.")
            var maxTokens: Int?

            @Option(
                name: .customLong("input-price"),
                help: "USD per million input tokens, to price drafts when the vendor reports none."
            )
            var inputPrice: Double?

            @Option(name: .customLong("output-price"), help: "USD per million output tokens.")
            var outputPrice: Double?

            @Option(
                name: .customLong("oauth-client-id"),
                help: "Client id of the OAuth app registered at the vendor (Hugging Face); enables `login`."
            )
            var oauthClientId: String?

            @Option(
                name: .customLong("oauth-client-secret"),
                help: "Client secret of that app, when the vendor issued one."
            )
            var oauthClientSecret: String?

            func run() async throws {
                try await failing {
                    let pricing = try (inputPrice ?? outputPrice).map { _ in
                        try AIPricing(inputPerMillion: inputPrice ?? 0, outputPerMillion: outputPrice ?? 0)
                    }
                    let provider = try AIProviderConfig(
                        id: id, kind: kind, name: name ?? id, model: model, baseURL: baseURL, apiKey: apiKey,
                        maxTokens: maxTokens, pricing: pricing,
                        oauth: oauthClientId.map { OAuthClientSettings(
                            clientId: $0,
                            clientSecret: oauthClientSecret
                        ) }
                    )
                    try await Output
                        .json(View(Runtime
                                .run(global) { try await $0.make(AIConfigCommandsKey.self).upsert(provider)
                                }))
                }
            }
        }

        struct Remove: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Remove a provider.")
            @OptionGroup var global: GlobalOptions
            @Argument var id: String

            func run() async throws {
                try await failing {
                    try await Output
                        .json(View(Runtime
                                .run(global) { try await $0.make(AIConfigCommandsKey.self).remove(id) }))
                }
            }
        }

        struct Default: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Make a provider the default.")
            @OptionGroup var global: GlobalOptions
            @Argument var id: String

            func run() async throws {
                try await failing {
                    try await Output
                        .json(View(Runtime
                                .run(global) { try await $0.make(AIConfigCommandsKey.self).setDefault(id) }))
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

        @Flag(help: "Show the provider's progress (stages, partial title) on stderr while drafting.")
        var stream = false

        func run() async throws {
            try await failing {
                try await Runtime.run(global) { services in
                    let boards = services.make(BoardCommandsKey.self)
                    let ref = ProjectRef.parse(project)
                    let all = try await boards.boards(ref)
                    guard let target = board
                        .map({ b in
                            all
                                .first {
                                    $0.name.caseInsensitiveCompare(b) == .orderedSame || $0.id.uuidString
                                        .caseInsensitiveCompare(b) == .orderedSame
                                } }) ?? all.first else {
                        throw ServiceError.domain(.notFound(board ?? "board"))
                    }

                    let assistant = services.make(AssistantCommandsKey.self)
                    let drafted = stream
                        ? try await Self.watch(assistant.streamTicket(
                            project: ref,
                            boardId: target.id,
                            idea: idea,
                            providerId: provider
                        ))
                        : try await assistant.draftTicket(
                            project: ref,
                            boardId: target.id,
                            idea: idea,
                            providerId: provider
                        )
                    if create {
                        let columns = try await boards.columns(ref, boardId: target.id)
                        guard let destination = column
                            .map({ c in
                                columns
                                    .first {
                                        $0.name.caseInsensitiveCompare(c) == .orderedSame || $0.id.uuidString
                                            .caseInsensitiveCompare(c) == .orderedSame
                                    } }) ?? columns.first else {
                            throw ServiceError.domain(.notFound(column ?? "column"))
                        }

                        let card = try await boards.createCard(
                            ref,
                            columnId: destination.id,
                            title: drafted.draft.title,
                            description: drafted.draft.cardDescription,
                            priority: drafted.draft.priority,
                            aiCost: drafted.aiCost,
                            subtasks: drafted.draft.subtasks.map(\.spec)
                        )
                        try Output.json(CreatedView(draft: drafted, card: card))
                    } else {
                        try Output.json(DraftView(drafted))
                    }
                }
            }
        }

        /// Narrates the stream on stderr and returns the result; stdout stays JSON-only.
        static func watch(_ events: AsyncThrowingStream<AssistantEvent, any Error>) async throws
            -> DraftedTicket {
            var lastTitle: String?
            for try await event in events {
                switch event {
                case let .stage(stage):
                    let elapsed = String(stage.elapsedMs)
                    let padding = String(repeating: " ", count: max(0, 6 - elapsed.count))
                    Output
                        .progress(
                            "[\(padding)\(elapsed)ms] \(stage.step.rawValue)\(stage.detail.map { ": " + $0 } ?? "")"
                        )
                case .text:
                    break
                case let .partial(partial):
                    if let title = partial.title, title != lastTitle {
                        lastTitle = title
                        Output.progress("          title: \(title)")
                    }
                case let .usage(usage):
                    let cost = usage.costUSD.map { ", \(usage.estimated ? "≈" : "")$" + String(
                        format: "%.4f",
                        $0
                    ) } ?? ""
                    Output
                        .progress(
                            "          tokens: \(usage.inputTokens ?? 0) in / \(usage.outputTokens ?? 0) out\(cost)"
                        )
                case let .result(drafted):
                    return drafted
                }
            }
            throw ServiceError.remote(code: "AI_PROVIDER", message: "stream ended without a result")
        }

        struct DraftView: Encodable {
            let draft: TicketDraft
            let provider: String
            let model: String
            let usage: CompletionUsage
            init(_ d: DraftedTicket) {
                self.draft = d.draft; self.provider = d.providerId; self.model = d.model; self.usage = d
                    .usage
            }
        }

        struct CreatedView: Encodable {
            let draft: DraftView
            let cardId: String
            let key: String
            enum CodingKeys: String, CodingKey { case draft, key; case cardId = "card_id" }
            init(draft: DraftedTicket, card: Card) {
                self.draft = DraftView(draft); self.cardId = card.id.uuidString.lowercased(); self
                    .key = "\(card.prefix)-\(card.cardNumber)"
            }
        }
    }
}

extension AIProviderKind: ExpressibleByArgument {}
