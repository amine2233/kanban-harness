import DashboardDomain
import Foundation

/// Wire enums use kanban-api's snake_case tokens; domain enums keep the persisted ones.
public struct PriorityDTO: Codable, Sendable, Equatable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ priority: CardPriority) { rawValue = priority.wireValue }
    public var domain: CardPriority? { CardPriority(wireValue: rawValue) }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct StatusDTO: Codable, Sendable, Equatable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ status: CardStatus) { rawValue = status.wireValue }
    public var domain: CardStatus? { CardStatus(wireValue: rawValue) }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BoardResponse: Codable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let sprintPrefix: String?
    public let cardPrefix: String?
    public let taskSortField: String
    public let taskSortOrder: String
    public let sprintDurationDays: Int?
    public let taskListView: String
    public let activeSprintId: UUID?
    public let position: Int
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, position
        case sprintPrefix = "sprint_prefix"
        case cardPrefix = "card_prefix"
        case taskSortField = "task_sort_field"
        case taskSortOrder = "task_sort_order"
        case sprintDurationDays = "sprint_duration_days"
        case taskListView = "task_list_view"
        case activeSprintId = "active_sprint_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(sprintPrefix, forKey: .sprintPrefix)
        try c.encode(cardPrefix, forKey: .cardPrefix)
        try c.encode(taskSortField, forKey: .taskSortField)
        try c.encode(taskSortOrder, forKey: .taskSortOrder)
        try c.encode(sprintDurationDays, forKey: .sprintDurationDays)
        try c.encode(taskListView, forKey: .taskListView)
        try c.encode(activeSprintId, forKey: .activeSprintId)
        try c.encode(position, forKey: .position)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    public init(_ board: Board) {
        id = board.id
        name = board.name
        description = board.description
        sprintPrefix = board.sprintPrefix
        cardPrefix = board.cardPrefix
        taskSortField = board.taskSortField.lowercased()
        taskSortOrder = board.taskSortOrder.lowercased()
        sprintDurationDays = board.sprintDurationDays
        taskListView = board.taskListView.lowercased()
        activeSprintId = board.activeSprintId
        position = board.position
        createdAt = board.createdAt
        updatedAt = board.updatedAt
    }
}

public struct ColumnResponse: Codable, Sendable, Equatable {
    public let id: UUID
    public let boardId: UUID
    public let name: String
    public let position: Int
    public let wipLimit: Int?
    public let defaultStatus: StatusDTO?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case boardId = "board_id"
        case wipLimit = "wip_limit"
        case defaultStatus = "default_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(boardId, forKey: .boardId)
        try c.encode(name, forKey: .name)
        try c.encode(position, forKey: .position)
        try c.encode(wipLimit, forKey: .wipLimit)
        try c.encode(defaultStatus, forKey: .defaultStatus)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    public init(_ column: Column) {
        id = column.id
        boardId = column.boardId
        name = column.name
        position = column.position
        wipLimit = column.wipLimit
        defaultStatus = column.defaultStatus.map(StatusDTO.init)
        createdAt = column.createdAt
        updatedAt = column.updatedAt
    }
}

public struct CardResponse: Codable, Sendable, Equatable {
    public let id: UUID
    public let columnId: UUID
    public let boardId: UUID
    public let prefix: String
    public let title: String
    public let description: String?
    public let priority: PriorityDTO
    public let status: StatusDTO
    public let position: Int
    public let dueDate: Date?
    public let points: Int?
    public let cardNumber: Int
    public let sprintId: UUID?
    public let aiCost: AICost?
    public let createdAt: Date
    public let updatedAt: Date
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, prefix, title, description, priority, status, position, points
        case columnId = "column_id"
        case boardId = "board_id"
        case dueDate = "due_date"
        case cardNumber = "card_number"
        case sprintId = "sprint_id"
        case aiCost = "ai_cost"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(columnId, forKey: .columnId)
        try c.encode(boardId, forKey: .boardId)
        try c.encode(prefix, forKey: .prefix)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(priority, forKey: .priority)
        try c.encode(status, forKey: .status)
        try c.encode(position, forKey: .position)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(points, forKey: .points)
        try c.encode(cardNumber, forKey: .cardNumber)
        try c.encode(sprintId, forKey: .sprintId)
        try c.encode(aiCost, forKey: .aiCost)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(completedAt, forKey: .completedAt)
    }

    public init(_ card: Card) {
        id = card.id
        columnId = card.columnId
        boardId = card.boardId
        prefix = card.prefix
        title = card.title
        description = card.description
        priority = PriorityDTO(card.priority)
        status = StatusDTO(card.status)
        position = card.position
        dueDate = card.dueDate
        points = card.points
        cardNumber = card.cardNumber
        sprintId = card.sprintId
        aiCost = card.aiCost
        createdAt = card.createdAt
        updatedAt = card.updatedAt
        completedAt = card.completedAt
    }
}
