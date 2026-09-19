import DashboardAPI
import DashboardDomain
import Vapor

extension Project: Content {}
extension BoardResponse: Content {}
extension ColumnResponse: Content {}
extension CardResponse: Content {}
extension CreateProjectRequest: Content {}
extension UpdateProjectRequest: Content {}
extension CreateCardRequest: Content {}
extension CreateBoardRequest: Content {}
extension UpdateBoardRequest: Content {}
extension CloneBoardRequest: Content {}
extension CreateColumnRequest: Content {}
extension UpdateColumnRequest: Content {}
extension UpdateCardRequest: Content {}
extension Page: Content {}
extension ApiError: Content {}

struct Health: Content {
    let status = "ok"
}

func routes(_ app: Vapor.Application, config: ServerConfig) throws {
    let api = app.grouped("api")
    api.get("health") { _ in Health() }
    try api.register(collection: ProjectsController())
    try api.grouped("projects", ":project", "kanban", "v1").register(collection: KanbanController())

    if let staticDir = config.staticDir {
        let index = (staticDir as NSString).appendingPathComponent("index.html")
        let spa: @Sendable (Request) async throws -> Response = { req in
            try await req.fileio.asyncStreamFile(at: index)
        }
        app.get(use: spa)
        app.get("**", use: spa)
    }
}

extension Request {
    func uuid(_ name: String) throws -> UUID {
        guard let id = parameters.get(name, as: UUID.self) else {
            throw Abort(.notFound, reason: "invalid \(name) id")
        }
        return id
    }

    var projectRef: ProjectRef {
        get throws { try .id(uuid("project")) }
    }
}
