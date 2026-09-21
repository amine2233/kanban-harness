import DashboardDomain
import DashboardPersistence
import Foundation

public let registryFormatVersion = 1

/// Project registry as one JSON file: `{ "version": 1, "projects": [...] }`.
public struct JSONProjectStore: ProjectStore {
    private struct Envelope: Codable {
        var version: Int
        var projects: [Project]
    }

    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func load() async throws -> [Project] {
        guard let data = try AtomicFile.read(path) else { return [] }
        let decoder = JSONDecoder()
        RFC3339.configure(decoder)
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
        guard envelope.version <= registryFormatVersion else {
            throw PersistenceError.unsupportedVersion(
                path: path, found: envelope.version, supported: registryFormatVersion
            )
        }
        return envelope.projects
    }

    public func save(_ projects: [Project]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        RFC3339.configure(encoder)
        let data = try encoder.encode(Envelope(version: registryFormatVersion, projects: projects))
        try AtomicFile.write(data, to: path)
    }
}
