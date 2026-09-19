import DashboardPersistenceFluent
import DashboardServer
import DashboardService
import Foundation

/// Boots the same registry the server uses, without a Vapor application.
struct CLIContext {
    let registry: SQLiteDatabase
    let pool: SQLiteDatabasePool
    let projects: ProjectService

    static func open(home: String) async throws -> CLIContext {
        let registry = try SQLiteDatabase.registry(path: ServerConfig(home: home).registryPath)
        try await registry.migrate()
        let pool = SQLiteDatabasePool()
        let projects = ProjectService(
            store: FluentProjectStore(database: registry.database),
            workspaces: WorkspaceStores.factory(pool: pool)
        )
        return CLIContext(registry: registry, pool: pool, projects: projects)
    }

    func run<T>(_ body: (ProjectService) async throws -> T) async throws -> T {
        do {
            let result = try await body(projects)
            await pool.shutdownAll()
            try await registry.shutdown()
            return result
        } catch {
            await pool.shutdownAll()
            try? await registry.shutdown()
            throw error
        }
    }
}
