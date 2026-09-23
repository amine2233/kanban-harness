import DashboardAPI
import DashboardDomain
import Vapor

extension Project: Content {}
extension Settings: Content {}
extension AIConfigDTO: Content {}
extension UpsertAIProviderRequest: Content {}
extension SetDefaultAIProviderRequest: Content {}
extension SignInResponse: Content {}
extension DraftTicketRequest: Content {}
extension DraftTicketResponse: Content {}
extension UpdateSettingsRequest: Content {}
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

extension HealthResponse: Content {}

func routes(_ app: Vapor.Application, config: ServerConfig) async throws {
    let api = app.grouped("api")
    // Answered from a value built at startup: the executable this process runs
    // may be replaced on disk while it keeps serving, and the point of the
    // field is to report the build it actually started from.
    let health = HealthResponse()
    api.get("health") { _ in health }
    try api.register(collection: ProjectsController())
    try api.register(collection: SettingsController())
    try api.register(collection: AIConfigController())
    try api.register(collection: AssistantController())
    try api.register(collection: EventsController())
    try await app.register(collection: MCPHost.start(app))
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
