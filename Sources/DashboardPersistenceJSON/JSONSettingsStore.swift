import DashboardDomain
import DashboardPersistence
import Foundation

/// `settings.json` in the dashboard home. Read on every `load`, so edits made
/// by hand or by another process are picked up without a restart.
public struct JSONSettingsStore: SettingsStore {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func load() async throws -> Settings {
        guard let data = try AtomicFile.read(path) else { return .default }

        do {
            return try JSONDecoder().decode(Settings.self, from: data).validated()
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
    }

    public func save(_ settings: Settings) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(encoder.encode(settings), to: path)
    }
}
