import DashboardDomain
import DashboardPersistence

/// Reads settings fresh on every call (no cache) so file edits apply live.
public actor SettingsService {
    private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    public func current() async throws(ServiceError) -> Settings {
        do {
            return try await store.load()
        } catch {
            throw ServiceError.wrap(error)
        }
    }

    /// Applies a partial change; `nil` fields keep their value.
    public func update(defaultStorage: StorageKind? = nil, corsOrigins: [String]? = nil) async throws(ServiceError) -> Settings {
        do {
            var settings = try await store.load()
            if let defaultStorage { settings.defaultStorage = defaultStorage }
            if let corsOrigins { settings.corsOrigins = corsOrigins }
            let validated = try settings.validated()
            try await store.save(validated)
            return validated
        } catch {
            throw ServiceError.wrap(error)
        }
    }
}
