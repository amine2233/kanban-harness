import DashboardAPI
import DashboardDomain
import Vapor

struct ProjectsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let projects = routes.grouped("projects")
        projects.get(use: list)
        projects.post(use: create)
        projects.group(":project") { project in
            project.get(use: show)
            project.patch(use: update)
            project.delete(use: remove)
        }
    }

    func list(req: Request) async throws -> [Project] {
        try await req.projects.list()
    }

    func create(req: Request) async throws -> Response {
        let body = try req.content.decode(CreateProjectRequest.self)
        let storage: StorageKind = if let requested = body.storage {
            requested
        } else {
            try await req.settings.current().defaultStorage
        }
        let project = try await req.projects.add(name: body.name, path: body.path, storage: storage)
        let response = Response(status: .created)
        try response.content.encode(project)
        return response
    }

    func show(req: Request) async throws -> Project {
        try await req.projects.get(req.projectRef)
    }

    func update(req: Request) async throws -> Project {
        let body = try req.content.decode(UpdateProjectRequest.self)
        return try await req.projects.changeStorage(req.projectRef, to: body.storage)
    }

    func remove(req: Request) async throws -> HTTPStatus {
        _ = try await req.projects.remove(req.projectRef)
        return .noContent
    }
}
