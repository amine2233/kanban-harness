import DashboardPersistence
import DashboardPersistenceFluent
import DashboardPersistenceJSON
import Fluent
import FluentSQLiteDriver
import Foundation
import Vapor

/// Single composition point for the HTTP app.
public func configure(_ app: Vapor.Application, config: ServerConfig) async throws {
    try FileManager.default.createDirectory(atPath: config.home, withIntermediateDirectories: true)
    app.databases.use(.sqlite(.file(config.registryPath)), as: .sqlite)
    for migration in FluentProjectStore.migrations {
        app.migrations.add(migration)
    }
    try await app.autoMigrate()

    let encoder = JSONEncoder()
    RFC3339.configure(encoder)
    let decoder = JSONDecoder()
    RFC3339.configure(decoder)
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    registerServices(app, config: config)
    app.middleware = Middlewares()
    app.middleware.use(DynamicCORSMiddleware(staticOrigins: config.corsOrigins))
    app.middleware.use(ApiErrorMiddleware())
    if let staticDir = config.staticDir {
        app.middleware.use(FileMiddleware(publicDirectory: staticDir))
    }

    try routes(app, config: config)
}
