import DashboardAI
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

public struct RemoteAIConfigCommands: AIConfigCommands {
    private let client: DashboardClient

    public init(client: DashboardClient) {
        self.client = client
    }

    public func current() async throws(ServiceError) -> AIConfig {
        try Self.config(try await client.send("GET", "api/settings/ai", body: Empty?.none, as: AIConfigDTO.self))
    }

    public func upsert(_ provider: AIProviderConfig) async throws(ServiceError) -> AIConfig {
        let body = UpsertAIProviderRequest(
            kind: provider.kind, name: provider.name, model: provider.model,
            baseURL: provider.baseURL, apiKey: provider.apiKey, maxTokens: provider.maxTokens, pricing: provider.pricing
        )
        return try Self.config(try await client.send("PUT", "api/settings/ai/providers/\(provider.id)", body: body, as: AIConfigDTO.self))
    }

    public func remove(_ id: String) async throws(ServiceError) -> AIConfig {
        try Self.config(try await client.send("DELETE", "api/settings/ai/providers/\(id)", body: Empty?.none, as: AIConfigDTO.self))
    }

    public func setDefault(_ id: String) async throws(ServiceError) -> AIConfig {
        try Self.config(try await client.send("PUT", "api/settings/ai/default", body: SetDefaultAIProviderRequest(providerId: id), as: AIConfigDTO.self))
    }

    /// The server never returns keys; the remote view carries `hasAPIKey` through a placeholder.
    private static func config(_ dto: AIConfigDTO) throws(ServiceError) -> AIConfig {
        do {
            return try AIConfig(
                providers: dto.providers.map { p in
                    try AIProviderConfig(
                        id: p.id, kind: p.kind, name: p.name, model: p.model, baseURL: p.baseURL,
                        apiKey: p.hasAPIKey ? RemoteAIConfigCommands.redactedKey : nil, maxTokens: p.maxTokens, pricing: p.pricing
                    )
                },
                defaultProviderId: dto.defaultProvider
            )
        } catch {
            throw .remote(code: "BAD_RESPONSE", message: String(describing: error))
        }
    }

    public static let redactedKey = "••••••••"
}

/// `BoardCommands` over the server's `/kanban/v1` API. Domain values are
/// rebuilt from the wire DTOs (fields the API does not expose keep defaults).
public struct RemoteBoardCommands: BoardCommands {
    private let client: DashboardClient
    private let projects: RemoteProjectCommands

    public init(client: DashboardClient) {
        self.client = client
        projects = RemoteProjectCommands(client: client)
    }

    private func base(_ project: ProjectRef) async throws(ServiceError) -> String {
        "api/projects/\(try await projects.get(project).id.uuidString)/kanban/v1"
    }

    public func boards(_ project: ProjectRef) async throws(ServiceError) -> [Board] {
        let page = try await client.send("GET", "\(try await base(project))/boards?page_size=500", body: Empty?.none, as: Page<BoardResponse>.self)
        return page.items.map(Self.board)
    }

    public func createBoard(_ project: ProjectRef, name: String, withDefaultColumns: Bool) async throws(ServiceError) -> Board {
        let body = CreateBoardRequest(name: name, withDefaultColumns: withDefaultColumns)
        return Self.board(try await client.send("POST", "\(try await base(project))/boards", body: body, as: BoardResponse.self))
    }

    public func columns(_ project: ProjectRef, boardId: UUID) async throws(ServiceError) -> [Column] {
        let page = try await client.send("GET", "\(try await base(project))/boards/\(boardId.uuidString)/columns?page_size=500", body: Empty?.none, as: Page<ColumnResponse>.self)
        return page.items.map(Self.column)
    }

    public func cards(_ project: ProjectRef, boardId: UUID) async throws(ServiceError) -> [Card] {
        let page = try await client.send("GET", "\(try await base(project))/boards/\(boardId.uuidString)/cards?page_size=500", body: Empty?.none, as: Page<CardResponse>.self)
        return page.items.compactMap(Self.card)
    }

    public func createCard(_ project: ProjectRef, columnId: UUID, title: String, description: String?, priority: CardPriority, aiCost: AICost?, subtasks: [SubtaskSpec]) async throws(ServiceError) -> Card {
        let body = CreateCardRequest(title: title, description: description, priority: PriorityDTO(priority), aiCost: aiCost, subtasks: subtasks.isEmpty ? nil : subtasks.map(SubtaskRequest.init))
        let response = try await client.send("POST", "\(try await base(project))/columns/\(columnId.uuidString)/cards", body: body, as: CardResponse.self)
        guard let card = Self.card(response) else { throw .remote(code: "BAD_RESPONSE", message: "unknown card enum values") }
        return card
    }

    public func children(_ project: ProjectRef, boardId: UUID, cardId: UUID) async throws(ServiceError) -> [Card] {
        let page = try await client.send("GET", "\(try await base(project))/boards/\(boardId.uuidString)/cards/\(cardId.uuidString)/children?page_size=500", body: Empty?.none, as: Page<CardResponse>.self)
        return page.items.compactMap(Self.card)
    }

    public func setParent(_ project: ProjectRef, boardId: UUID, cardId: UUID, parentId: UUID?) async throws(ServiceError) -> Card {
        let response = try await client.send("PUT", "\(try await base(project))/boards/\(boardId.uuidString)/cards/\(cardId.uuidString)/parent", body: SetParentRequest(parentId: parentId), as: CardResponse.self)
        guard let card = Self.card(response) else { throw .remote(code: "BAD_RESPONSE", message: "unknown card enum values") }
        return card
    }

    public func updateCard(_ project: ProjectRef, boardId: UUID, cardId: UUID, changes: CardChanges) async throws(ServiceError) -> Card {
        let body = UpdateCardRequest(
            title: changes.title,
            priority: changes.priority.map(PriorityDTO.init),
            status: changes.status.map(StatusDTO.init),
            columnId: changes.columnId,
            description: Self.patch(changes.description),
            dueDate: Self.patch(changes.dueDate),
            points: Self.patch(changes.points)
        )
        let response = try await client.send("PATCH", "\(try await base(project))/boards/\(boardId.uuidString)/cards/\(cardId.uuidString)", body: body, as: CardResponse.self)
        guard let card = Self.card(response) else { throw .remote(code: "BAD_RESPONSE", message: "unknown card enum values") }
        return card
    }

    public func deleteCard(_ project: ProjectRef, boardId: UUID, cardId: UUID) async throws(ServiceError) {
        try await client.send("DELETE", "\(try await base(project))/boards/\(boardId.uuidString)/cards/\(cardId.uuidString)", body: Empty?.none)
    }

    private static func patch<T: Codable & Sendable & Equatable>(_ value: T??) -> Patch<T> {
        switch value {
        case .none: .keep
        case .some(.none): .clear
        case let .some(.some(v)): .set(v)
        }
    }

    private static func board(_ r: BoardResponse) -> Board {
        var board = Board(name: r.name, position: r.position, id: r.id, now: r.createdAt)
        board.description = r.description
        board.cardPrefix = r.cardPrefix
        board.sprintPrefix = r.sprintPrefix
        board.updatedAt = r.updatedAt
        return board
    }

    private static func column(_ r: ColumnResponse) -> Column {
        var column = Column(boardId: r.boardId, name: r.name, position: r.position, wipLimit: r.wipLimit, defaultStatus: r.defaultStatus.flatMap(\.domain), id: r.id, now: r.createdAt)
        column.updatedAt = r.updatedAt
        return column
    }

    private static func card(_ r: CardResponse) -> Card? {
        guard let priority = r.priority.domain, let status = r.status.domain else { return nil }
        var card = Card(boardId: r.boardId, columnId: r.columnId, prefix: r.prefix, cardNumber: r.cardNumber, title: r.title, description: r.description, priority: priority, status: status, position: r.position, id: r.id, now: r.createdAt)
        card.dueDate = r.dueDate
        card.points = r.points
        card.aiCost = r.aiCost
        card.sprintId = r.sprintId
        card.updatedAt = r.updatedAt
        card.completedAt = r.completedAt
        return card
    }
}

public struct RemoteAssistantCommands: AssistantCommands {
    private let client: DashboardClient
    private let projects: RemoteProjectCommands

    public init(client: DashboardClient) {
        self.client = client
        projects = RemoteProjectCommands(client: client)
    }

    /// Consumes the server's event stream and maps each frame back to an `AssistantEvent`.
    public func streamTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let id = try await projects.get(project).id
                    let request = DraftTicketRequest(idea: idea, boardId: boardId, provider: providerId)
                    var parser = SSEParser()
                    for try await line in client.eventStream("POST", "api/projects/\(id.uuidString)/ai/tickets/draft", body: request) {
                        guard let (event, data) = parser.feed(line: line), let frame = try AssistantFrame.decode(event: event, data: data) else { continue }
                        switch frame {
                        case let .stage(stage):
                            guard let step = AssistantStage.Step(rawValue: stage.step) else { continue }
                            continuation.yield(.stage(AssistantStage(step, detail: stage.detail, elapsedMs: stage.elapsedMs)))
                        case let .text(text): continuation.yield(.text(text.delta))
                        case let .partial(partial): continuation.yield(.partial(partial))
                        case let .usage(usage): continuation.yield(.usage(Self.usage(usage)))
                        case let .result(response):
                            continuation.yield(.result(DraftedTicket(draft: response.draft, providerId: response.provider, model: response.model, usage: Self.usage(response.usage))))
                        case let .error(apiError): throw ServiceError.remote(code: apiError.code, message: apiError.message)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func usage(_ dto: DraftTicketResponse.UsageDTO) -> CompletionUsage {
        CompletionUsage(inputTokens: dto.inputTokens, outputTokens: dto.outputTokens, costUSD: dto.costUSD, estimated: dto.estimated)
    }
}
