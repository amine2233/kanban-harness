import CascadeKit
import DashboardRuntime
import DashboardService
import Vapor

private struct ContainerKey: Vapor.StorageKey {
    typealias Value = CascadeKit.Application
}

private struct RequestContainerKey: Vapor.StorageKey {
    typealias Value = CascadeKit.Request
}

/// Per-request value, resolved from the request container (never from the app's).
public enum RequestIdKey: ServiceKey {
    public typealias Value = UUID
}

extension Vapor.Application {
    /// The cascade-kit container owning application-scoped services (see `DashboardRuntime`).
    public var services: CascadeKit.Application {
        if let container = storage[ContainerKey.self] { return container }
        let container = CascadeKit.Application()
        storage[ContainerKey.self] = container
        return container
    }
}

extension Vapor.Request {
    /// Request-scoped container layered over the application's: request-only
    /// services live here, everything else falls through to the app container.
    public var services: CascadeKit.Request {
        if let container = storage[RequestContainerKey.self] { return container }
        let container = CascadeKit.Request(application: application.services)
        let id = DependencyValues.current.uuid()
        container.register(RequestIdKey.self) { _ in id }
        storage[RequestContainerKey.self] = container
        return container
    }

    public var requestId: UUID { services.make(RequestIdKey.self) }
    public var projects: ProjectService { services.make(ProjectServiceKey.self) }
    public var settings: SettingsService { services.make(SettingsServiceKey.self) }
    public var aiConfig: any AIConfigCommands { services.make(AIConfigCommandsKey.self) }
}

func registerServices(_ app: Vapor.Application, config: ServerConfig) async throws {
    try await DashboardRuntime.register(on: app.services, config: config.runtime, registryDatabase: app.db)
    app.lifecycle.use(ShutdownRuntime())
}

private struct ShutdownRuntime: LifecycleHandler {
    func shutdownAsync(_ application: Vapor.Application) async {
        await DashboardRuntime.shutdown(application.services)
    }
}
