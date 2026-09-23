import DashboardDomain

/// Where the AI provider configuration lives. Backends own the file format;
/// the rules live in `AIConfig`.
public protocol AIConfigStore: Sendable {
    /// The configuration, `.empty` when nothing is stored yet.
    func load() async throws -> AIConfig
    func save(_ config: AIConfig) async throws
}

public actor AIConfigStoreInMemory: AIConfigStore {
    private var config = AIConfig.empty

    public init() {}

    public func load() async throws -> AIConfig {
        config
    }

    public func save(_ config: AIConfig) async throws {
        self.config = config
    }
}

extension StoreContract {
    /// used only for unit-test
    public static func verify(_ store: any AIConfigStore) async throws {
        let fresh = try await store.load()
        try require(fresh == .empty, "fresh store must be empty")
        let config = try AIConfig(
            providers: [
                AIProviderConfig(
                    id: "claude",
                    kind: .anthropic,
                    name: "Claude",
                    model: "claude-sonnet-5",
                    apiKey: "sk-secret",
                    maxTokens: 4_096
                ),
                AIProviderConfig(
                    id: "local",
                    kind: .ollama,
                    name: "Ollama",
                    model: "llama3.2",
                    baseURL: "http://127.0.0.1:11434"
                )
            ],
            defaultProviderId: "local"
        )
        try await store.save(config)
        let loaded = try await store.load()
        try require(loaded == config, "save then load must round-trip, secrets included")
        try await store.save(.empty)
        let cleared = try await store.load()
        try require(cleared == .empty, "saving empty must clear")
    }
}
