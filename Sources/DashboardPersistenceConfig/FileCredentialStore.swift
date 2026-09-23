import DashboardDomain
import DashboardPersistence
import Foundation

/// `credentials.json` next to the config file, mode 0600, written atomically —
/// the fallback every CLI ends up with (gh, aws, docker) and the only option
/// on a headless Linux box.
public struct FileCredentialStore: CredentialStore {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func get(_ providerId: String) async throws -> Credential? {
        try read()[providerId]
    }

    public func set(_ credential: Credential, for providerId: String) async throws {
        var all = try read()
        all[providerId] = credential
        try write(all)
    }

    public func remove(_ providerId: String) async throws {
        var all = try read()
        guard all.removeValue(forKey: providerId) != nil else { return }

        try write(all)
    }

    private func read() throws -> [String: Credential] {
        guard let data = try AtomicFile.read(path), !data.isEmpty else { return [:] }

        do {
            return try Self.decoder.decode([String: Credential].self, from: data)
        } catch {
            throw PersistenceError.corrupt(path: path, reason: error.localizedDescription)
        }
    }

    private func write(_ all: [String: Credential]) throws {
        let data: Data
        do {
            data = try Self.encoder.encode(all)
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
        try AtomicFile.write(data, to: path, mode: 0o600)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        RFC3339.configure(encoder)
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        RFC3339.configure(decoder)
        return decoder
    }()
}
