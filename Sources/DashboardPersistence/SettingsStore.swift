import DashboardDomain

public protocol SettingsStore: Sendable {
    /// Current settings; defaults when nothing is stored.
    func load() async throws -> Settings
    func save(_ settings: Settings) async throws
}

public actor SettingsStoreInMemory: SettingsStore {
    private var settings = Settings.default

    public init() {}

    public func load() async throws -> Settings {
        settings
    }

    public func save(_ settings: Settings) async throws {
        self.settings = settings
    }
}

extension StoreContract {
    public static func verify(_ store: any SettingsStore) async throws {
        let fresh = try await store.load()
        try require(fresh == .default, "fresh store must yield defaults")
        let custom = Settings(defaultStorage: .sqlite, corsOrigins: ["http://localhost:5173"])
        try await store.save(custom)
        let loaded = try await store.load()
        try require(loaded == custom, "save then load must round-trip")
        try await store.save(.default)
        let reset = try await store.load()
        try require(reset == .default, "saving defaults must restore them")
    }
}
