import DashboardPersistenceFluent
import DashboardPersistenceJSON
import DashboardServer
import DashboardService
import Foundation

/// Boots the same registry the server uses, without a Vapor application.
struct CLIContext {
    let registry: SQLiteRegistry
    let projects: ProjectService

    static func open(home: String) async throws -> CLIContext {
        let registry = try SQLiteRegistry(path: ServerConfig(home: home).registryPath)
        try await registry.migrate()
        let projects = ProjectService(
            store: registry.store(),
            workspaces: WorkspaceStoreFactory { KanbanJSONStore(path: $0.dataFile) }
        )
        return CLIContext(registry: registry, projects: projects)
    }

    func run<T>(_ body: (ProjectService) async throws -> T) async throws -> T {
        do {
            let result = try await body(projects)
            try await registry.shutdown()
            return result
        } catch {
            try? await registry.shutdown()
            throw error
        }
    }
}
