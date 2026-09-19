import DashboardDomain
import DashboardPersistence
import FluentKit

/// Kanban workspace on any Fluent database. Same aggregate, same contract as
/// `KanbanJSONStore`: `save` replaces the whole workspace in one transaction.
public struct FluentWorkspaceStore: WorkspaceStore {
    public let database: any Database

    public static let migrations: [any Migration] = [CreateWorkspaceSchema()]

    public init(database: any Database) {
        self.database = database
    }

    public func load() async throws -> Workspace {
        var extra: [String: JSONValue] = [:]
        for section in try await SectionModel.query(on: database).all() {
            guard let key = section.id else { continue }
            extra[key] = try JSONText.decode(section.json)
        }
        return Workspace(
            boards: try await BoardModel.query(on: database).sort(\.$position).all().map { try $0.toDomain() },
            columns: try await ColumnModel.query(on: database).sort(\.$position).all().map { try $0.toDomain() },
            cards: try await CardModel.query(on: database).sort(\.$cardNumber).all().map { try $0.toDomain() },
            prefixes: try await PrefixModel.query(on: database).all().map { try $0.toDomain() },
            extra: extra
        )
    }

    public func save(_ workspace: Workspace) async throws {
        try await database.transaction { db in
            try await CardModel.query(on: db).delete()
            try await ColumnModel.query(on: db).delete()
            try await BoardModel.query(on: db).delete()
            try await PrefixModel.query(on: db).delete()
            try await SectionModel.query(on: db).delete()
            for board in workspace.boards {
                try await BoardModel(board).create(on: db)
            }
            for column in workspace.columns {
                try await ColumnModel(column).create(on: db)
            }
            for card in workspace.cards {
                try await CardModel(card).create(on: db)
            }
            for prefix in workspace.prefixes {
                try await PrefixModel(prefix).create(on: db)
            }
            for (key, value) in workspace.extra {
                try await SectionModel(key: key, value: value).create(on: db)
            }
        }
    }
}

/// `WorkspaceStore` over a SQLite file, resolved lazily from a shared pool so
/// the synchronous `WorkspaceStoreFactory` can hand it out per request.
public struct SQLiteWorkspaceStore: WorkspaceStore {
    public let path: String
    public let pool: SQLiteDatabasePool

    public init(path: String, pool: SQLiteDatabasePool) {
        self.path = path
        self.pool = pool
    }

    public func load() async throws -> Workspace {
        try await FluentWorkspaceStore(database: try await pool.database(at: path)).load()
    }

    public func save(_ workspace: Workspace) async throws {
        try await FluentWorkspaceStore(database: try await pool.database(at: path)).save(workspace)
    }
}
