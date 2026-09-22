import FluentKit
import FluentSQLiteDriver
import Foundation
import Logging
import NIOCore
import NIOPosix

/// One standalone Fluent SQLite database file (no Vapor `Application`), with
/// its migrations. Used by the CLI and for per-project workspace files; the
/// server registers the same driver and migrations on its own app instead.
public final class SQLiteDatabase: Sendable {
    public static let defaultNumberOfThreads = 2

    public let path: String
    private let threadPool: NIOThreadPool
    private let databases: Databases
    private let migrations: [any Migration]
    private let logger: Logger
    /// The one event loop this file's connection lives on.
    ///
    /// Handing `Databases` a whole `MultiThreadedEventLoopGroup` gives the driver one
    /// SQLite connection *per loop* on the same file, and `MultiThreadedEventLoopGroup.any()`
    /// hands out whichever loop the caller happens to be on. Two of those connections
    /// writing at once hit `SQLITE_BUSY`, and sqlite-nio installs a busy handler that
    /// retries forever while holding a thread-pool thread — that is the
    /// `[AsyncKit] Connection request timed out` deadlock. A single-loop group means
    /// exactly one connection per file, because FluentSQLiteDriver pins
    /// `maxConnectionsPerEventLoop` to 1 regardless of what it is passed.
    ///
    /// ponytail: per-file parallelism needs WAL plus a bounded busy handler upstream,
    /// not more threads; serialising one file is what makes this safe.
    private let eventLoop: any EventLoop

    public init(
        path: String,
        migrations: [any Migration],
        logger: Logger = Logger(label: "dashboard.sqlite"),
        numberOfThreads: Int = SQLiteDatabase.defaultNumberOfThreads,
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) throws {
        self.path = path
        self.migrations = migrations
        self.logger = logger
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        threadPool = NIOThreadPool(numberOfThreads: max(1, numberOfThreads))
        threadPool.start()
        eventLoop = eventLoopGroup.next()
        databases = Databases(threadPool: threadPool, on: eventLoop)
        databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    /// The project registry database.
    public static func registry(
        path: String,
        logger: Logger = Logger(label: "dashboard.sqlite"),
        numberOfThreads: Int = SQLiteDatabase.defaultNumberOfThreads
    ) throws -> SQLiteDatabase {
        try SQLiteDatabase(path: path, migrations: FluentProjectStore.migrations, logger: logger, numberOfThreads: numberOfThreads)
    }

    /// A project's kanban workspace database.
    public static func workspace(
        path: String,
        logger: Logger = Logger(label: "dashboard.sqlite"),
        numberOfThreads: Int = SQLiteDatabase.defaultNumberOfThreads
    ) throws -> SQLiteDatabase {
        try SQLiteDatabase(path: path, migrations: FluentWorkspaceStore.migrations, logger: logger, numberOfThreads: numberOfThreads)
    }

    public var database: any Database {
        databases.database(.sqlite, logger: logger, on: eventLoop)!
    }

    public func migrate() async throws {
        let bundle = Migrations()
        for migration in migrations {
            bundle.add(migration)
        }
        let migrator = Migrator(
            databases: databases,
            migrations: bundle,
            logger: logger,
            on: eventLoop
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()
    }

    public func shutdown() async throws {
        await databases.shutdownAsync()
        try await threadPool.shutdownGracefully()
    }
}

/// Keeps one open, migrated database per file for the life of the process,
/// so request-scoped stores don't pay for a thread pool and migration each time.
public actor SQLiteDatabasePool {
    private var open: [String: Task<SQLiteDatabase, any Error>] = [:]
    private let make: @Sendable (String) throws -> SQLiteDatabase

    public init(make: @escaping @Sendable (String) throws -> SQLiteDatabase) {
        self.make = make
    }

    public init(
        logger: Logger = Logger(label: "dashboard.sqlite"),
        numberOfThreads: Int = SQLiteDatabase.defaultNumberOfThreads
    ) {
        self.init { try SQLiteDatabase.workspace(path: $0, logger: logger, numberOfThreads: numberOfThreads) }
    }

    public func database(at path: String) async throws -> any Database {
        let opening = opening(at: path)
        do {
            return try await opening.value.database
        } catch {
            // A failed open must not poison the path for every later caller.
            if open[path] == opening { open[path] = nil }
            throw error
        }
    }

    /// Synchronous on purpose: callers racing on the same path find the in-flight
    /// task instead of each opening and migrating a database only to discard it.
    private func opening(at path: String) -> Task<SQLiteDatabase, any Error> {
        if let existing = open[path] { return existing }
        let make = self.make
        let task = Task {
            let database = try make(path)
            do {
                try await database.migrate()
            } catch {
                try? await database.shutdown()
                throw error
            }
            return database
        }
        open[path] = task
        return task
    }

    public func close(_ path: String) async throws {
        guard let opening = open.removeValue(forKey: path) else { return }
        guard let database = try? await opening.value else { return }
        try await database.shutdown()
    }

    public func shutdownAll() async {
        let opening = open.values
        open.removeAll()
        for task in opening {
            guard let database = try? await task.value else { continue }
            try? await database.shutdown()
        }
    }
}
