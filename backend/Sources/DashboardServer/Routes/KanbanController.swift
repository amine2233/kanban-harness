import DashboardAPI
import DashboardDomain
import Vapor

/// The kanban `/v1` API served per project: boards, columns and cards.
struct KanbanController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("boards", use: listBoards)
        routes.post("boards", use: createBoard)
        routes.patch("boards", ":board", use: updateBoard)
        routes.delete("boards", ":board", use: deleteBoard)
        routes.post("boards", ":board", "clone", use: cloneBoard)

        routes.get("boards", ":board", "columns", use: listColumns)
        routes.post("boards", ":board", "columns", use: createColumn)
        routes.patch("boards", ":board", "columns", ":column", use: updateColumn)
        routes.delete("boards", ":board", "columns", ":column", use: deleteColumn)

        routes.get("boards", ":board", "cards", use: listCards)
        routes.post("columns", ":column", "cards", use: createCard)
        routes.patch("boards", ":board", "cards", ":card", use: updateCard)
        routes.delete("boards", ":board", "cards", ":card", use: deleteCard)
    }

    // MARK: Boards

    func listBoards(req: Request) async throws -> Page<BoardResponse> {
        let workspace = try await req.projects.workspace(req.projectRef)
        let boards = workspace.boards.sorted { $0.position < $1.position }.map(BoardResponse.init)
        return try req.query.decode(PageParams.self).paginate(boards)
    }

    func createBoard(req: Request) async throws -> Response {
        let body = try req.content.decode(CreateBoardRequest.self)
        guard !body.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Abort(.badRequest, reason: "board name must not be empty") }
        let board = try await req.projects.mutate(req.projectRef) { workspace, now in
            let board = body.withDefaultColumns ?? true
                ? workspace.createBoardWithTemplateColumns(name: body.name, now: now)
                : workspace.createBoard(name: body.name, now: now)
            return try workspace.updateBoard(board.id, description: .some(body.description), cardPrefix: .some(body.cardPrefix), now: now)
        }
        return try created(BoardResponse(board))
    }

    func updateBoard(req: Request) async throws -> BoardResponse {
        let body = try req.content.decode(UpdateBoardRequest.self)
        let boardId = try req.uuid("board")
        let board = try await req.projects.mutate(req.projectRef) { workspace, now in
            if let position = body.position {
                try workspace.moveBoard(boardId, toPosition: position, now: now)
            }
            return try workspace.updateBoard(
                boardId, name: body.name, description: body.description.value, cardPrefix: body.cardPrefix.value, now: now
            )
        }
        return BoardResponse(board)
    }

    func deleteBoard(req: Request) async throws -> HTTPStatus {
        let boardId = try req.uuid("board")
        try await req.projects.mutate(req.projectRef) { workspace, _ in
            try workspace.deleteBoard(boardId)
        }
        return .noContent
    }

    func cloneBoard(req: Request) async throws -> Response {
        let body = (try? req.content.decode(CloneBoardRequest.self)) ?? CloneBoardRequest()
        let boardId = try req.uuid("board")
        let board = try await req.projects.mutate(req.projectRef) { workspace, now in
            try workspace.cloneBoard(boardId, name: body.name, now: now)
        }
        return try created(BoardResponse(board))
    }

    // MARK: Columns

    func listColumns(req: Request) async throws -> Page<ColumnResponse> {
        let workspace = try await req.projects.workspace(req.projectRef)
        let board = try workspace.board(req.uuid("board"))
        return try req.query.decode(PageParams.self).paginate(workspace.columns(of: board.id).map(ColumnResponse.init))
    }

    func createColumn(req: Request) async throws -> Response {
        let body = try req.content.decode(CreateColumnRequest.self)
        let boardId = try req.uuid("board")
        guard !body.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Abort(.badRequest, reason: "column name must not be empty") }
        let status = try body.defaultStatus.map(Self.status)
        let column = try await req.projects.mutate(req.projectRef) { workspace, now in
            try workspace.createColumn(boardId: boardId, name: body.name, wipLimit: body.wipLimit, defaultStatus: status, now: now)
        }
        return try created(ColumnResponse(column))
    }

    func updateColumn(req: Request) async throws -> ColumnResponse {
        let body = try req.content.decode(UpdateColumnRequest.self)
        let boardId = try req.uuid("board")
        let columnId = try req.uuid("column")
        let status: CardStatus?? = switch body.defaultStatus {
        case .keep: nil
        case .clear: .some(nil)
        case let .set(dto): .some(try Self.status(dto))
        }
        let column = try await req.projects.mutate(req.projectRef) { workspace, now in
            try Self.requireColumn(columnId, in: boardId, workspace)
            if let position = body.position {
                try workspace.moveColumn(columnId, toPosition: position, now: now)
            }
            return try workspace.updateColumn(columnId, name: body.name, wipLimit: body.wipLimit.value, defaultStatus: status, now: now)
        }
        return ColumnResponse(column)
    }

    func deleteColumn(req: Request) async throws -> HTTPStatus {
        let boardId = try req.uuid("board")
        let columnId = try req.uuid("column")
        try await req.projects.mutate(req.projectRef) { workspace, _ in
            try Self.requireColumn(columnId, in: boardId, workspace)
            try workspace.deleteColumn(columnId)
        }
        return .noContent
    }

    // MARK: Cards

    func listCards(req: Request) async throws -> Page<CardResponse> {
        let workspace = try await req.projects.workspace(req.projectRef)
        let board = try workspace.board(req.uuid("board"))
        return try req.query.decode(PageParams.self).paginate(workspace.cards(of: board.id).map(CardResponse.init))
    }

    func createCard(req: Request) async throws -> Response {
        let body = try req.content.decode(CreateCardRequest.self)
        let columnId = try req.uuid("column")
        let priority = try body.priority.map(Self.priority)
        let card = try await req.projects.mutate(req.projectRef) { workspace, now in
            try workspace.createCard(
                columnId: columnId, title: body.title, description: body.description, priority: priority ?? .medium, now: now
            )
        }
        return try created(CardResponse(card))
    }

    func updateCard(req: Request) async throws -> CardResponse {
        let body = try req.content.decode(UpdateCardRequest.self)
        let boardId = try req.uuid("board")
        let cardId = try req.uuid("card")
        let priority = try body.priority.map(Self.priority)
        let status = try body.status.map(Self.status)
        let card = try await req.projects.mutate(req.projectRef) { workspace, now in
            try Self.requireCard(cardId, in: boardId, workspace)
            if let targetBoard = body.boardId, targetBoard != boardId {
                try workspace.moveCardToBoard(cardId, boardId: targetBoard, columnId: body.columnId, now: now)
            } else if let columnId = body.columnId {
                try workspace.moveCard(cardId, toColumn: columnId, now: now)
            }
            return try workspace.updateCard(
                cardId, title: body.title, description: body.description.value, priority: priority,
                status: status, dueDate: body.dueDate.value, points: body.points.value, now: now
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

    // MARK: Helpers

    private func created(_ body: some Content) throws -> Response {
        let response = Response(status: .created)
        try response.content.encode(body)
        return response
    }

    private static func priority(_ dto: PriorityDTO) throws -> CardPriority {
        guard let value = dto.domain else { throw Abort(.badRequest, reason: "unknown priority '\(dto.rawValue)'") }
        return value
    }

    private static func status(_ dto: StatusDTO) throws -> CardStatus {
        guard let value = dto.domain else { throw Abort(.badRequest, reason: "unknown status '\(dto.rawValue)'") }
        return value
    }

    private static func requireCard(_ cardId: UUID, in boardId: UUID, _ workspace: Workspace) throws {
        guard try workspace.card(cardId).boardId == boardId else { throw DomainError.cardNotFound(cardId) }
    }

    private static func requireColumn(_ columnId: UUID, in boardId: UUID, _ workspace: Workspace) throws {
        guard try workspace.column(columnId).boardId == boardId else { throw DomainError.columnNotFound(columnId) }
    }
}
