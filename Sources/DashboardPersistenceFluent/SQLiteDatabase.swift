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
    public let path: String
    private let threadPool: NIOThreadPool
    private let databases: Databases
    private let migrations: [any Migration]
    private let logger: Logger

    public init(path: String, migrations: [any Migration], logger: Logger = Logger(label: "dashboard.sqlite")) throws {
        self.path = path
        self.migrations = migrations
        self.logger = logger
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        databases = Databases(threadPool: threadPool, on: MultiThreadedEventLoopGroup.singleton)
        databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    /// The project registry database.
    public static func registry(path: String, logger: Logger = Logger(label: "dashboard.sqlite")) throws -> SQLiteDatabase {
        try SQLiteDatabase(path: path, migrations: FluentProjectStore.migrations, logger: logger)
    }

    /// A project's kanban workspace database.
    public static func workspace(path: String, logger: Logger = Logger(label: "dashboard.sqlite")) throws -> SQLiteDatabase {
        try SQLiteDatabase(path: path, migrations: FluentWorkspaceStore.migrations, logger: logger)
    }

    public var database: any Database {
        databases.database(.sqlite, logger: logger, on: MultiThreadedEventLoopGroup.singleton.any())!
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
            on: MultiThreadedEventLoopGroup.singleton.any()
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
    private var open: [String: SQLiteDatabase] = [:]
    private let make: @Sendable (String) throws -> SQLiteDatabase

    public init(make: @escaping @Sendable (String) throws -> SQLiteDatabase) {
        self.make = make
    }

    public init(logger: Logger = Logger(label: "dashboard.sqlite")) {
        self.init { try SQLiteDatabase.workspace(path: $0, logger: logger) }
    }

    public func database(at path: String) async throws -> any Database {
        if let existing = open[path] { return existing.database }
        let database = try make(path)
        do {
            try await database.migrate()
        } catch {
            try? await database.shutdown()
            throw error
        }
        open[path] = database
        return database.database
    }

    public func close(_ path: String) async throws {
        guard let database = open.removeValue(forKey: path) else { return }
        try await database.shutdown()
    }

    public func shutdownAll() async {
        let databases = open.values
        open.removeAll()
        for database in databases {
            try? await database.shutdown()
        }
    }
}
