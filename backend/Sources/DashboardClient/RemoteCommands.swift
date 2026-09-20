import DashboardAPI
import DashboardDomain
import DashboardService
import Foundation

/// `ProjectCommands` over HTTP. Names are resolved client-side from the list,
/// since the server's routes take ids.
public struct RemoteProjectCommands: ProjectCommands {
    private let client: DashboardClient

    public init(client: DashboardClient) {
        self.client = client
    }

    public func list() async throws(ServiceError) -> [Project] {
        try await client.send("GET", "api/projects", body: Empty?.none, as: [Project].self)
    }

    public func get(_ reference: ProjectRef) async throws(ServiceError) -> Project {
        if case let .id(id) = reference {
            return try await client.send("GET", "api/projects/\(id.uuidString)", body: Empty?.none, as: Project.self)
        }
        guard let match = try await list().first(where: reference.matches) else {
            throw .remote(code: "NOT_FOUND", message: "project not found: \(reference)")
        }
        return match
    }

    public func add(name: String, path: String, storage: StorageKind?) async throws(ServiceError) -> Project {
        try await client.send("POST", "api/projects", body: CreateProjectRequest(name: name, path: path, storage: storage), as: Project.self)
    }

    public func remove(_ reference: ProjectRef) async throws(ServiceError) -> Project {
        let project = try await get(reference)
        try await client.send("DELETE", "api/projects/\(project.id.uuidString)", body: Empty?.none)
        return project
    }

    public func changeStorage(_ reference: ProjectRef, to storage: StorageKind) async throws(ServiceError) -> Project {
        let project = try await get(reference)
        return try await client.send(
            "PATCH", "api/projects/\(project.id.uuidString)", body: UpdateProjectRequest(storage: storage), as: Project.self
        )
    }

    public func boards(_ reference: ProjectRef) async throws(ServiceError) -> [BoardSummary] {
        let project = try await get(reference)
        let page = try await client.send(
            "GET", "api/projects/\(project.id.uuidString)/kanban/v1/boards?page_size=500", body: Empty?.none, as: Page<BoardResponse>.self
        )
        return page.items.map {
            BoardSummary(id: $0.id, name: $0.name, description: $0.description, cardPrefix: $0.cardPrefix, position: $0.position)
        }
    }
}

public struct RemoteSettingsCommands: SettingsCommands {
    private let client: DashboardClient

    public init(client: DashboardClient) {
        self.client = client
    }

    public func current() async throws(ServiceError) -> Settings {
        try await client.send("GET", "api/settings", body: Empty?.none, as: Settings.self)
    }

    public func update(defaultStorage: StorageKind?, corsOrigins: [String]?) async throws(ServiceError) -> Settings {
        try await client.send(
            "PATCH", "api/settings",
            body: UpdateSettingsRequest(defaultStorage: defaultStorage, corsOrigins: corsOrigins), as: Settings.self
        )
    }
}
