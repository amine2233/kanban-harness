import CascadeKit
import DashboardPersistence
import DashboardPersistenceFluent
import DashboardPersistenceJSON
import DashboardService
import Vapor

/// cascade-kit service keys resolved from the Vapor application's container.
public enum ProjectServiceKey: ServiceKey {
    public typealias Value = ProjectService
}

public enum ProjectStoreKey: ServiceKey {
    public typealias Value = any ProjectStore
}

private struct ContainerKey: Vapor.StorageKey {
    typealias Value = CascadeKit.Application
}

extension Vapor.Application {
    /// The cascade-kit container owning application-scoped services.
    public var services: CascadeKit.Application {
        if let container = storage[ContainerKey.self] { return container }
        let container = CascadeKit.Application()
        storage[ContainerKey.self] = container
        return container
    }
}

extension Vapor.Request {
    public var projects: ProjectService {
        application.services.make(ProjectServiceKey.self)
    }
}

/// Default wiring: registry in Fluent SQLite, board data in kanban-rs JSON files.
func registerServices(_ app: Vapor.Application) {
    let database = app.db
    app.services.register(ProjectStoreKey.self) { _ in FluentProjectStore(database: database) }
    app.services.register(ProjectServiceKey.self) { container in
        ProjectService(
            store: container.make(ProjectStoreKey.self),
            workspaces: WorkspaceStoreFactory { KanbanJSONStore(path: $0.dataFile) }
        )
    }
}
