import DashboardDomain
import DashboardPersistence

/// Edits the AI provider configuration; every change is persisted and broadcast.
public actor AIConfigService: AIConfigCommands {
    private let store: any AIConfigStore
    private let changes: ChangeBroadcaster

    public init(store: any AIConfigStore, changes: ChangeBroadcaster = ChangeBroadcaster()) {
        self.store = store
        self.changes = changes
    }

    public func current() async throws(ServiceError) -> AIConfig {
        do {
            return try await store.load()
        } catch {
            throw ServiceError.wrap(error)
        }
    }

    public func upsert(_ provider: AIProviderConfig) async throws(ServiceError) -> AIConfig {
        try await mutate { try $0.upsert(provider) }
    }

    public func remove(_ id: String) async throws(ServiceError) -> AIConfig {
        try await mutate { try $0.remove(id) }
    }

    public func setDefault(_ id: String) async throws(ServiceError) -> AIConfig {
        try await mutate { try $0.setDefault(id) }
    }

    private func mutate(_ body: (inout AIConfig) throws -> Void) async throws(ServiceError) -> AIConfig {
        do {
            var config = try await store.load()
            try body(&config)
            try await store.save(config)
            await changes.publish(.aiConfigChanged)
            return config
        } catch {
            throw ServiceError.wrap(error)
        }
    }
}
