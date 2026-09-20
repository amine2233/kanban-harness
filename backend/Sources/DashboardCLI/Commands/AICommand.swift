import ArgumentParser
import DashboardDomain
import DashboardRuntime
import DashboardService

struct AICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai",
        abstract: "AI assistant configuration (providers live in config.json / config.yaml).",
        subcommands: [Providers.self]
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

extension AIProviderKind: ExpressibleByArgument {}
