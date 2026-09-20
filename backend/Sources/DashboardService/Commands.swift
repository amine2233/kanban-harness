import DashboardDomain
import Foundation

/// What a board looks like to callers that don't need the full aggregate (CLI listings).
public struct BoardSummary: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let cardPrefix: String?
    public let position: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description, position
        case cardPrefix = "card_prefix"
    }

    public init(id: UUID, name: String, description: String?, cardPrefix: String?, position: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.cardPrefix = cardPrefix
        self.position = position
    }

    public init(_ board: Board) {
        self.init(id: board.id, name: board.name, description: board.description, cardPrefix: board.cardPrefix, position: board.position)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(cardPrefix, forKey: .cardPrefix)
        try container.encode(position, forKey: .position)
    }
}

/// The project operations a front end (CLI, later others) drives. Implemented
/// locally by `ProjectService` and remotely by the HTTP client, so a caller
/// never knows whether it owns the files or talks to the server that does.
public protocol ProjectCommands: Sendable {
    func list() async throws(ServiceError) -> [Project]
    func get(_ reference: ProjectRef) async throws(ServiceError) -> Project
    func add(name: String, path: String, storage: StorageKind?) async throws(ServiceError) -> Project
    func remove(_ reference: ProjectRef) async throws(ServiceError) -> Project
    func changeStorage(_ reference: ProjectRef, to storage: StorageKind) async throws(ServiceError) -> Project
    func boards(_ reference: ProjectRef) async throws(ServiceError) -> [BoardSummary]
}

public protocol SettingsCommands: Sendable {
    func current() async throws(ServiceError) -> Settings
    func update(defaultStorage: StorageKind?, corsOrigins: [String]?) async throws(ServiceError) -> Settings
}

/// AI provider configuration, editable from the web and the CLI alike.
public protocol AIConfigCommands: Sendable {
    func current() async throws(ServiceError) -> AIConfig
    func upsert(_ provider: AIProviderConfig) async throws(ServiceError) -> AIConfig
    func remove(_ id: String) async throws(ServiceError) -> AIConfig
    func setDefault(_ id: String) async throws(ServiceError) -> AIConfig
}

extension SettingsService: SettingsCommands {}

/// Local implementation: owns the files. `storage: nil` falls back to the settings default.
public struct LocalProjectCommands: ProjectCommands {
    private let projects: ProjectService
    private let settings: SettingsService

    public init(projects: ProjectService, settings: SettingsService) {
        self.projects = projects
        self.settings = settings
    }

    public func list() async throws(ServiceError) -> [Project] { try await projects.list() }
    public func get(_ reference: ProjectRef) async throws(ServiceError) -> Project { try await projects.get(reference) }

    public func add(name: String, path: String, storage: StorageKind?) async throws(ServiceError) -> Project {
        let kind: StorageKind
        if let storage {
            kind = storage
        } else {
            kind = try await settings.current().defaultStorage
        }
        return try await projects.add(name: name, path: path, storage: kind)
    }

    public func remove(_ reference: ProjectRef) async throws(ServiceError) -> Project { try await projects.remove(reference) }

    public func changeStorage(_ reference: ProjectRef, to storage: StorageKind) async throws(ServiceError) -> Project {
        try await projects.changeStorage(reference, to: storage)
    }

    public func boards(_ reference: ProjectRef) async throws(ServiceError) -> [BoardSummary] {
        try await projects.workspace(reference).boards.sorted { $0.position < $1.position }.map(BoardSummary.init)
    }
}

// MARK: - Boards and cards

/// Partial card update; `nil` keeps a field, `.some(nil)` clears an optional one.
public struct CardChanges: Equatable, Sendable {
    public var title: String?
    public var description: String??
    public var priority: CardPriority?
    public var status: CardStatus?
    public var points: Int??
    public var dueDate: Date??
    public var columnId: UUID?

    public init(
        title: String? = nil, description: String?? = nil, priority: CardPriority? = nil,
        status: CardStatus? = nil, points: Int?? = nil, dueDate: Date?? = nil, columnId: UUID? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.points = points
        self.dueDate = dueDate
        self.columnId = columnId
    }
}

/// Board-level operations a front end drives (MCP tools, later others).
/// Local: mutates the workspace under the service actor. Remote: the server's `/kanban/v1` API.
public protocol BoardCommands: Sendable {
    func boards(_ project: ProjectRef) async throws(ServiceError) -> [Board]
    func createBoard(_ project: ProjectRef, name: String, withDefaultColumns: Bool) async throws(ServiceError) -> Board
    func columns(_ project: ProjectRef, boardId: UUID) async throws(ServiceError) -> [Column]
    func cards(_ project: ProjectRef, boardId: UUID) async throws(ServiceError) -> [Card]
    func createCard(_ project: ProjectRef, columnId: UUID, title: String, description: String?, priority: CardPriority, aiCost: AICost?) async throws(ServiceError) -> Card
    func updateCard(_ project: ProjectRef, boardId: UUID, cardId: UUID, changes: CardChanges) async throws(ServiceError) -> Card
    func deleteCard(_ project: ProjectRef, boardId: UUID, cardId: UUID) async throws(ServiceError)
}

public struct LocalBoardCommands: BoardCommands {
    private let projects: ProjectService

    public init(projects: ProjectService) {
        self.projects = projects
    }

    public func boards(_ project: ProjectRef) async throws(ServiceError) -> [Board] {
        try await projects.workspace(project).boards.sorted { $0.position < $1.position }
    }

    public func createBoard(_ project: ProjectRef, name: String, withDefaultColumns: Bool) async throws(ServiceError) -> Board {
        try await projects.mutate(project) { workspace, now in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DomainError.emptyBoardName }
            return withDefaultColumns
                ? workspace.createBoardWithTemplateColumns(name: trimmed, now: now)
                : workspace.createBoard(name: trimmed, now: now)
        }
    }

    public func columns(_ project: ProjectRef, boardId: UUID) async throws(ServiceError) -> [Column] {
        let workspace = try await projects.workspace(project)
        do {
            _ = try workspace.board(boardId)
        } catch {
            throw ServiceError.wrap(error)
        }
        return workspace.columns(of: boardId)
    }

    public func cards(_ project: ProjectRef, boardId: UUID) async throws(ServiceError) -> [Card] {
        let workspace = try await projects.workspace(project)
        do {
            _ = try workspace.board(boardId)
        } catch {
            throw ServiceError.wrap(error)
        }
        return workspace.cards(of: boardId)
    }

    public func createCard(_ project: ProjectRef, columnId: UUID, title: String, description: String?, priority: CardPriority, aiCost: AICost?) async throws(ServiceError) -> Card {
        try await projects.mutate(project) { workspace, now in
            try workspace.createCard(columnId: columnId, title: title, description: description, priority: priority, aiCost: aiCost, now: now)
        }
    }

    public func updateCard(_ project: ProjectRef, boardId: UUID, cardId: UUID, changes: CardChanges) async throws(ServiceError) -> Card {
        try await projects.mutate(project) { workspace, now in
            guard try workspace.card(cardId).boardId == boardId else { throw DomainError.cardNotFound(cardId) }
            if let columnId = changes.columnId {
                try workspace.moveCard(cardId, toColumn: columnId, now: now)
            }
            return try workspace.updateCard(
                cardId, title: changes.title, description: changes.description, priority: changes.priority,
                status: changes.status, dueDate: changes.dueDate, points: changes.points, now: now
            )
        }
    }

    public func deleteCard(_ project: ProjectRef, boardId: UUID, cardId: UUID) async throws(ServiceError) {
        try await projects.mutate(project) { workspace, _ in
            guard try workspace.card(cardId).boardId == boardId else { throw DomainError.cardNotFound(cardId) }
            try workspace.deleteCard(cardId)
        }
    }
}
