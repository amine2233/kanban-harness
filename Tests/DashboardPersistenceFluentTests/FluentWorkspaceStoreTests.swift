import DashboardDomain
import DashboardPersistence
import DashboardPersistenceJSON
import FluentSQLiteDriver
import Foundation
import Testing
@testable import DashboardPersistenceFluent

@Suite(.serialized) struct FluentWorkspaceStoreTests {
    func tempDir() throws -> String {
        let path = NSTemporaryDirectory() + "mvp-dashboard-fluent-ws-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    func fixtureWorkspace() async throws -> Workspace {
        let url = try #require(Bundle.module.url(forResource: "kanban-v18", withExtension: "json", subdirectory: "Fixtures"))
        let path = try tempDir() + "/kanban.json"
        try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: path))
        return try await KanbanJSONStore(path: path).load()
    }

    @Test func sqliteStoreSatisfiesTheSameContractAsJSON() async throws {
        let database = try SQLiteDatabase.workspace(path: try tempDir() + "/kanban.sqlite")
        try await database.migrate()
        try await StoreContract.verify(FluentWorkspaceStore(database: database.database))
        try await database.shutdown()
    }

    @Test func existingDatabasesGainTheAICostColumn() async throws {
        let path = try tempDir() + "/kanban.sqlite"
        let old = try SQLiteDatabase(path: path, migrations: [CreateWorkspaceSchema()])
        try await old.migrate()
        try await old.shutdown()

        let current = try SQLiteDatabase.workspace(path: path)
        try await current.migrate()
        let store = FluentWorkspaceStore(database: current.database)
        do {
            var workspace = try await store.load()
            let board = workspace.createBoardWithTemplateColumns(name: "Upgraded")
            try workspace.createCard(columnId: workspace.columns(of: board.id)[0].id, title: "After", aiCost: AICost(provider: "cc", model: "sonnet", costUSD: 0.01))
            try await store.save(workspace)
            #expect(try await store.load().cards.first?.aiCost?.costUSD == 0.01)
        } catch {
            try await current.shutdown()
            throw error
        }
        try await current.shutdown()
    }

    @Test func aiCostMigrationSkipsFilesThatAlreadyHaveTheColumn() async throws {
        let path = try tempDir() + "/kanban.sqlite"
        let old = try SQLiteDatabase(path: path, migrations: [CreateWorkspaceSchema()])
        try await old.migrate()
        try await old.shutdown()
        let plain = try SQLiteDatabase(path: path, migrations: [])
        let sql = try #require(plain.database as? any SQLDatabase)
        try await sql.raw("ALTER TABLE cards ADD COLUMN ai_cost TEXT").run()
        try await plain.shutdown()

        let pool = SQLiteDatabasePool()
        _ = try await pool.database(at: path)
        try await StoreContract.verify(SQLiteWorkspaceStore(path: path, pool: pool))
        await pool.shutdownAll()
    }

    @Test func pooledStoreSatisfiesContractAndReusesOneDatabase() async throws {
        let pool = SQLiteDatabasePool()
        let path = try tempDir() + "/kanban.sqlite"
        try await StoreContract.verify(SQLiteWorkspaceStore(path: path, pool: pool))
        _ = try await pool.database(at: path)
        await pool.shutdownAll()
    }

    @Test func jsonToSQLiteToJSONIsLossless() async throws {
        let original = try await fixtureWorkspace()
        let pool = SQLiteDatabasePool()
        let sqlite = SQLiteWorkspaceStore(path: try tempDir() + "/kanban.sqlite", pool: pool)
        try await sqlite.save(original)
        let fromSQLite = try await sqlite.load()
        #expect(fromSQLite == original)

        let json = KanbanJSONStore(path: try tempDir() + "/kanban.json")
        try await json.save(fromSQLite)
        let backToJSON = try await json.load()
        #expect(backToJSON == original)
        #expect(backToJSON.extra["sprints"]?.arrayValue?.count == 1)
        #expect(backToJSON.extra["graph"] == original.extra["graph"])
        await pool.shutdownAll()
    }

    @Test func mutationsBehaveIdenticallyOnBothBackends() async throws {
        let pool = SQLiteDatabasePool()
        let stores: [any WorkspaceStore] = [
            KanbanJSONStore(path: try tempDir() + "/kanban.json"),
            SQLiteWorkspaceStore(path: try tempDir() + "/kanban.sqlite", pool: pool),
        ]
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var results: [Workspace] = []
        for store in stores {
            var workspace = try await fixtureWorkspace()
            let board = workspace.boards[0]
            let columns = workspace.columns(of: board.id)
            let card = try workspace.createCard(columnId: columns[0].id, title: "Same everywhere", id: UUID(uuidString: "0e0e0e0e-0e0e-4e0e-8e0e-0e0e0e0e0e0e")!, now: now)
            try workspace.moveCard(card.id, toColumn: columns[2].id, now: now)
            try await store.save(workspace)
            results.append(try await store.load())
        }
        #expect(results[0] == results[1])
        #expect(results[0].cards.count == 2)
        #expect(results[0].prefixes.first { $0.name == "task" }?.cardCounter == 2)
        await pool.shutdownAll()
    }

    @Test func sqliteRowsAreHumanReadable() async throws {
        let database = try SQLiteDatabase.workspace(path: try tempDir() + "/kanban.sqlite")
        try await database.migrate()
        var workspace = Workspace()
        let board = workspace.createBoardWithTemplateColumns(name: "Readable", now: Date(timeIntervalSince1970: 1.5))
        try workspace.createCard(columnId: workspace.columns(of: board.id)[2].id, title: "x", now: Date(timeIntervalSince1970: 2))
        try await FluentWorkspaceStore(database: database.database).save(workspace)
        let card = try #require(try await CardModel.query(on: database.database).first())
        #expect(card.status == "InProgress")
        #expect(card.createdAt == "1970-01-01T00:00:02.000000Z")
        #expect(card.sprintLogs == "[]")
        try await database.shutdown()
    }

    @Test func corruptRowSurfacesAsPersistenceError() async throws {
        let database = try SQLiteDatabase.workspace(path: try tempDir() + "/kanban.sqlite")
        try await database.migrate()
        var workspace = Workspace()
        workspace.createBoard(name: "B")
        let store = FluentWorkspaceStore(database: database.database)
        try await store.save(workspace)
        let row = try #require(try await BoardModel.query(on: database.database).first())
        row.createdAt = "yesterday"
        try await row.update(on: database.database)
        await #expect(throws: PersistenceError.self) {
            try await store.load()
        }
        try await database.shutdown()
    }
}
