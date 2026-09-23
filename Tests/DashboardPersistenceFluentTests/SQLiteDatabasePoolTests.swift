import DashboardDomain
import DashboardPersistence
import Foundation
import Testing
@testable import DashboardPersistenceFluent

/// Regression cover for the `[AsyncKit] Connection request timed out` deadlock:
/// the pool used to hand a file's `Databases` the whole event loop group, which
/// gave the driver one SQLite connection per loop. Two of them writing the same
/// file deadlocked against sqlite-nio's retry-forever busy handler.
@Suite(.serialized)
struct SQLiteDatabasePoolTests {
    func path() -> String {
        NSTemporaryDirectory() + "mvp-dashboard-pool-" + UUID().uuidString + "/workspace.sqlite"
    }

    func workspace(_ name: String) throws -> Workspace {
        var workspace = Workspace()
        let board = workspace.createBoardWithTemplateColumns(name: name)
        try workspace.createCard(columnId: workspace.columns(of: board.id)[0].id, title: name)
        return workspace
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentWritesToOneFileDoNotDeadlock() async throws {
        let pool = SQLiteDatabasePool()
        let store = SQLiteWorkspaceStore(path: path(), pool: pool)
        try await store.save(workspace("seed"))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 24 {
                group.addTask {
                    _ = try await store.load()
                    try await store.save(workspace("board-\(index)"))
                }
            }
            try await group.waitForAll()
        }

        #expect(try await store.load().boards.count == 1)
        await pool.shutdownAll()
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentWritesAcrossFilesDoNotDeadlock() async throws {
        let pool = SQLiteDatabasePool()
        let paths = (0 ..< 6).map { _ in path() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for path in paths {
                for index in 0 ..< 4 {
                    group.addTask {
                        let store = SQLiteWorkspaceStore(path: path, pool: pool)
                        try await store.save(workspace("board-\(index)"))
                        _ = try await store.load()
                    }
                }
            }
            try await group.waitForAll()
        }

        await pool.shutdownAll()
    }

    @Test
    func racingCallersShareOneOpenAndMigration() async throws {
        let opened = Counter()
        let path = path()
        let pool = SQLiteDatabasePool { path in
            opened.increment()
            return try SQLiteDatabase.workspace(path: path)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 16 {
                group.addTask { _ = try await pool.database(at: path) }
            }
            try await group.waitForAll()
        }

        #expect(opened.value == 1)
        await pool.shutdownAll()
    }

    @Test
    func aFailedOpenIsNotCachedForever() async throws {
        let attempts = Counter()
        let pool = SQLiteDatabasePool { path in
            attempts.increment()
            if attempts.value == 1 { throw PersistenceError.corrupt(path: path, reason: "boom") }
            return try SQLiteDatabase.workspace(path: path)
        }
        let path = path()

        await #expect(throws: (any Error).self) { _ = try await pool.database(at: path) }
        _ = try await pool.database(at: path)
        #expect(attempts.value == 2)
        await pool.shutdownAll()
    }

    @Test
    func closeReopensOnTheNextAccess() async throws {
        let opened = Counter()
        let pool = SQLiteDatabasePool { path in
            opened.increment()
            return try SQLiteDatabase.workspace(path: path)
        }
        let path = path()

        _ = try await pool.database(at: path)
        try await pool.close(path)
        _ = try await pool.database(at: path)

        #expect(opened.value == 2)
        await pool.shutdownAll()
    }
}

/// `SQLiteDatabasePool.make` is a `@Sendable` closure, so the tests count through
/// a lock rather than an actor they would have to await inside it.
final class Counter: Sendable {
    private let storage = NSLock()
    private nonisolated(unsafe) var count = 0

    func increment() {
        storage.lock()
        count += 1
        storage.unlock()
    }

    var value: Int {
        storage.lock()
        defer { storage.unlock() }
        return count
    }
}
