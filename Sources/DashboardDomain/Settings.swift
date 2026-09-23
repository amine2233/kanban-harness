import Foundation

/// Server-side configuration, editable at runtime. Validation lives here so
/// every entry point (API, CLI, hand-edited file) enforces the same rules.
public struct Settings: Codable, Equatable, Sendable {
    public var defaultStorage: StorageKind
    /// Browser origins allowed to call the API from another host; empty = same origin only.
    public var corsOrigins: [String]

    enum CodingKeys: String, CodingKey {
        case defaultStorage = "default_storage"
        case corsOrigins = "cors_origins"
    }

    public static let `default` = Settings(defaultStorage: .json, corsOrigins: [])

    public init(defaultStorage: StorageKind = .json, corsOrigins: [String] = []) {
        self.defaultStorage = defaultStorage
        self.corsOrigins = corsOrigins
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultStorage = try container
            .decodeIfPresent(StorageKind.self, forKey: .defaultStorage) ?? .json
        self.corsOrigins = try container.decodeIfPresent([String].self, forKey: .corsOrigins) ?? []
    }

    /// Normalises and validates an origin: scheme + host[:port], no path, http(s) only.
    public static func normaliseOrigin(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.path.isEmpty || url.path == "/", url.query == nil
        else { throw DomainError.invalidOrigin(trimmed) }

        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host.lowercased())\(port)"
    }

    public func validated() throws -> Settings {
        var copy = self
        copy.corsOrigins = try corsOrigins.map(Self.normaliseOrigin)
        var seen = Set<String>()
        copy.corsOrigins = copy.corsOrigins.filter { seen.insert($0).inserted }
        return copy
    }
}
