import FluentKit
import FluentSQLiteDriver
import Foundation
import Logging
import NIOCore
import NIOPosix

/// Boots a standalone Fluent SQLite database (no Vapor `Application`) for
/// processes like the CLI; the server registers the driver on its own app instead.
public final class SQLiteRegistry: Sendable {
    public let path: String
    private let threadPool: NIOThreadPool
    private let databases: Databases
    private let logger: Logger

    public init(path: String, logger: Logger = Logger(label: "dashboard.sqlite")) throws {
        self.path = path
        self.logger = logger
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        databases = Databases(threadPool: threadPool, on: MultiThreadedEventLoopGroup.singleton)
        databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    public var database: any Database {
        databases.database(.sqlite, logger: logger, on: MultiThreadedEventLoopGroup.singleton.any())!
    }

    public func migrate() async throws {
        let migrator = Migrator(
            databases: databases,
            migrations: {
                let migrations = Migrations()
                for migration in FluentProjectStore.migrations {
                    migrations.add(migration)
                }
                return migrations
            }(),
            logger: logger,
            on: MultiThreadedEventLoopGroup.singleton.any()
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()
    }

    public func store() -> FluentProjectStore {
        FluentProjectStore(database: database)
    }

    public func shutdown() async throws {
        await databases.shutdownAsync()
        try await threadPool.shutdownGracefully()
    }
}
