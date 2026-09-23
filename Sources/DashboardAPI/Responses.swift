import DashboardDomain
import Foundation

/// Wire enums use kanban-api's snake_case tokens; domain enums keep the persisted ones.
public struct PriorityDTO: Codable, Sendable, Equatable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ priority: CardPriority) {
        self.rawValue = priority.wireValue
    }

    public var domain: CardPriority? {
        CardPriority(wireValue: rawValue)
    }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct StatusDTO: Codable, Sendable, Equatable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ status: CardStatus) {
        self.rawValue = status.wireValue
    }

    public var domain: CardStatus? {
        CardStatus(wireValue: rawValue)
    }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
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
        case id
        case name
        case description
        case position
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
        self.id = board.id
        self.name = board.name
        self.description = board.description
        self.sprintPrefix = board.sprintPrefix
        self.cardPrefix = board.cardPrefix
        self.taskSortField = board.taskSortField.lowercased()
        self.taskSortOrder = board.taskSortOrder.lowercased()
        self.sprintDurationDays = board.sprintDurationDays
        self.taskListView = board.taskListView.lowercased()
        self.activeSprintId = board.activeSprintId
        self.position = board.position
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
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
        case id
        case name
        case position
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
        self.id = column.id
        self.boardId = column.boardId
        self.name = column.name
        self.position = column.position
        self.wipLimit = column.wipLimit
        self.defaultStatus = column.defaultStatus.map(StatusDTO.init)
        self.createdAt = column.createdAt
        self.updatedAt = column.updatedAt
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
    public let parentId: UUID?
    public let children: ChildrenDTO
    public let createdAt: Date
    public let updatedAt: Date
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case prefix
        case title
        case description
        case priority
        case status
        case position
        case points
        case columnId = "column_id"
        case boardId = "board_id"
        case dueDate = "due_date"
        case cardNumber = "card_number"
        case sprintId = "sprint_id"
        case aiCost = "ai_cost"
        case parentId = "parent_id"
        case children
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }

    public struct ChildrenDTO: Codable, Sendable, Equatable {
        public let total: Int
        public let done: Int

        public init(total: Int, done: Int) {
            self.total = total
            self.done = done
        }
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
        try c.encode(parentId, forKey: .parentId)
        try c.encode(children, forKey: .children)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(completedAt, forKey: .completedAt)
    }

    public init(_ card: Card, in workspace: Workspace) {
        self.parentId = workspace.parent(of: card.id)
        let progress = workspace.progress(of: card.id)
        self.children = ChildrenDTO(total: progress.total, done: progress.done)
        self.id = card.id
        self.columnId = card.columnId
        self.boardId = card.boardId
        self.prefix = card.prefix
        self.title = card.title
        self.description = card.description
        self.priority = PriorityDTO(card.priority)
        self.status = StatusDTO(card.status)
        self.position = card.position
        self.dueDate = card.dueDate
        self.points = card.points
        self.cardNumber = card.cardNumber
        self.sprintId = card.sprintId
        self.aiCost = card.aiCost
        self.createdAt = card.createdAt
        self.updatedAt = card.updatedAt
        self.completedAt = card.completedAt
    }
}
