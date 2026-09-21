import DashboardDomain
import DashboardPersistence
import Foundation

/// The kanban-rs JSON store format version this backend reads and writes.
/// Older files must be migrated once by the `kanban` CLI; newer ones are refused.
public let kanbanFormatVersion = 18

/// Reads/writes a kanban-rs `kanban.json` envelope `{ version, metadata, data }`
/// without depending on the Rust crates. Only boards/columns/cards/prefixes
/// are interpreted; everything else in `data` is preserved byte-for-byte in meaning.
public struct KanbanJSONStore: WorkspaceStore {
    private struct Metadata: Codable {
        var instanceId: UUID
        var savedAt: Date
        var writerVersion: String?
        var writerCommit: String?

        enum CodingKeys: String, CodingKey {
            case instanceId = "instance_id"
            case savedAt = "saved_at"
            case writerVersion = "writer_version"
            case writerCommit = "writer_commit"
        }
    }

    private struct Envelope: Codable {
        var version: Int
        var metadata: Metadata
        var data: [String: JSONValue]
    }

    static let writerVersion = "0.9.0+mvp-dashboard"
    private static let modelledKeys = ["boards", "columns", "cards", "prefixes"]

    public let path: String
    public let instanceId: UUID

    public init(path: String, instanceId: UUID = UUID()) {
        self.path = path
        self.instanceId = instanceId
    }

    public func load() async throws -> Workspace {
        guard let data = try AtomicFile.read(path) else { return Workspace() }
        let envelope: Envelope
        do {
            envelope = try Self.decoder().decode(Envelope.self, from: data)
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
        guard envelope.version == kanbanFormatVersion else {
            throw PersistenceError.unsupportedVersion(
                path: path, found: envelope.version, supported: kanbanFormatVersion
            )
        }
        return try decodeWorkspace(envelope.data)
    }

    public func save(_ workspace: Workspace) async throws {
        let envelope = Envelope(
            version: kanbanFormatVersion,
            metadata: Metadata(
                instanceId: instanceId,
                savedAt: Date(),
                writerVersion: Self.writerVersion,
                writerCommit: "unknown"
            ),
            data: try encodeWorkspace(workspace)
        )
        let encoder = Self.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let tree = try Self.decoder().decode(JSONValue.self, from: Self.encoder().encode(envelope))
        try AtomicFile.write(try encoder.encode(tree.lowercasingUUIDs()), to: path)
    }

    private func decodeWorkspace(_ data: [String: JSONValue]) throws -> Workspace {
        func section<T: Decodable>(_ key: String, as _: T.Type) throws -> [T] {
            guard let value = data[key] else { return [] }
            do {
                return try Self.decoder().decode([T].self, from: Self.encoder().encode(value))
            } catch {
                throw PersistenceError.corrupt(path: path, reason: "\(key): \(error)")
            }
        }
        return Workspace(
            boards: try section("boards", as: Board.self),
            columns: try section("columns", as: Column.self),
            cards: try section("cards", as: Card.self),
            prefixes: try section("prefixes", as: Prefix.self),
            extra: data.filter { !Self.modelledKeys.contains($0.key) }
        )
    }

    private func encodeWorkspace(_ workspace: Workspace) throws -> [String: JSONValue] {
        func section(_ value: some Encodable) throws -> JSONValue {
            try Self.decoder().decode(JSONValue.self, from: Self.encoder().encode(value))
        }
        var data = workspace.extra
        data["boards"] = try section(workspace.boards)
        data["columns"] = try section(workspace.columns)
        data["cards"] = try section(workspace.cards)
        data["prefixes"] = try section(workspace.prefixes)
        for key in ["archived_boards", "archived_cards", "sprints"] where data[key] == nil {
            data[key] = .array([])
        }
        if data["graph"] == nil {
            data["graph"] = .object([
                "blocks": .object(["edges": .array([])]),
                "relates": .object(["edges": .array([])]),
                "spawns": .object(["edges": .array([])]),
            ])
        }
        return data
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        RFC3339.configure(decoder)
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        RFC3339.configure(encoder)
        return encoder
    }
}
