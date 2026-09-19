import DashboardAPI
import DashboardDomain
import Vapor

/// The subset of kanban-server's `/v1` API the dashboard uses, served per project.
struct KanbanController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("boards", use: listBoards)
        routes.get("boards", ":board", "columns", use: listColumns)
        routes.get("boards", ":board", "cards", use: listCards)
        routes.post("columns", ":column", "cards", use: createCard)
        routes.patch("boards", ":board", "cards", ":card", use: updateCard)
        routes.delete("boards", ":board", "cards", ":card", use: deleteCard)
    }

    func listBoards(req: Request) async throws -> Page<BoardResponse> {
        let workspace = try await req.projects.workspace(req.projectRef)
        let boards = workspace.boards.sorted { $0.position < $1.position }.map(BoardResponse.init)
        return try req.query.decode(PageParams.self).paginate(boards)
    }

    func listColumns(req: Request) async throws -> Page<ColumnResponse> {
        let workspace = try await req.projects.workspace(req.projectRef)
        let board = try workspace.board(req.uuid("board"))
        return try req.query.decode(PageParams.self).paginate(workspace.columns(of: board.id).map(ColumnResponse.init))
    }

    func listCards(req: Request) async throws -> Page<CardResponse> {
        let workspace = try await req.projects.workspace(req.projectRef)
        let board = try workspace.board(req.uuid("board"))
        return try req.query.decode(PageParams.self).paginate(workspace.cards(of: board.id).map(CardResponse.init))
    }

    func createCard(req: Request) async throws -> Response {
        let body = try req.content.decode(CreateCardRequest.self)
        let columnId = try req.uuid("column")
        let priority = try body.priority.map { dto -> CardPriority in
            guard let priority = dto.domain else {
                throw Abort(.badRequest, reason: "unknown priority '\(dto.rawValue)'")
            }
            return priority
        }
        let card = try await req.projects.mutate(req.projectRef) { workspace, now in
            try workspace.createCard(
                columnId: columnId,
                title: body.title,
                description: body.description,
                priority: priority ?? .medium,
                now: now
            )
        }
        let response = Response(status: .created)
        try response.content.encode(CardResponse(card))
        return response
    }

    func updateCard(req: Request) async throws -> CardResponse {
        let body = try req.content.decode(UpdateCardRequest.self)
        let boardId = try req.uuid("board")
        let cardId = try req.uuid("card")
        let priority = try body.priority.map { dto -> CardPriority in
            guard let value = dto.domain else { throw Abort(.badRequest, reason: "unknown priority '\(dto.rawValue)'") }
            return value
        }
        let status = try body.status.map { dto -> CardStatus in
            guard let value = dto.domain else { throw Abort(.badRequest, reason: "unknown status '\(dto.rawValue)'") }
            return value
        }
        let card = try await req.projects.mutate(req.projectRef) { workspace, now in
            try Self.requireCard(cardId, in: boardId, workspace)
            if let columnId = body.columnId {
                try workspace.moveCard(cardId, toColumn: columnId, now: now)
            }
            return try workspace.updateCard(
                cardId,
                title: body.title,
                description: body.description.value,
                priority: priority,
                status: status,
                now: now
            )
        }
        return CardResponse(card)
    }

    func deleteCard(req: Request) async throws -> HTTPStatus {
        let boardId = try req.uuid("board")
        let cardId = try req.uuid("card")
        try await req.projects.mutate(req.projectRef) { workspace, _ in
            try Self.requireCard(cardId, in: boardId, workspace)
            try workspace.deleteCard(cardId)
        }
        return .noContent
    }

    private static func requireCard(_ cardId: UUID, in boardId: UUID, _ workspace: Workspace) throws {
        guard try workspace.card(cardId).boardId == boardId else { throw DomainError.cardNotFound(cardId) }
    }
}
