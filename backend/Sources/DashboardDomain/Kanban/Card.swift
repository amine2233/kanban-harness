import Foundation

/// Raw values are the PascalCase tokens kanban-rs persists; `wireValue` is the
/// snake_case token its REST API and this server expose.
public enum CardStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case todo = "Todo"
    case inProgress = "InProgress"
    case blocked = "Blocked"
    case done = "Done"

    public var wireValue: String {
        switch self {
        case .todo: "todo"
        case .inProgress: "in_progress"
        case .blocked: "blocked"
        case .done: "done"
        }
    }

    public init?(wireValue: String) {
        guard let match = Self.allCases.first(where: { $0.wireValue == wireValue }) else { return nil }
        self = match
    }
}

public enum CardPriority: String, Codable, Hashable, Sendable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    public var wireValue: String { rawValue.lowercased() }

    public init?(wireValue: String) {
        guard let match = Self.allCases.first(where: { $0.wireValue == wireValue }) else { return nil }
        self = match
    }
}

public struct Card: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let boardId: UUID
    public var columnId: UUID
    public var prefix: String
    public var cardNumber: Int
    public var title: String
    public var description: String?
    public var priority: CardPriority
    public var status: CardStatus
    public var position: Int
    public var dueDate: Date?
    public var points: Int?
    public var sprintId: UUID?
    public var sprintLogs: [JSONValue]
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, prefix, title, description, priority, status, position, points
        case boardId = "board_id"
        case columnId = "column_id"
        case cardNumber = "card_number"
        case dueDate = "due_date"
        case sprintId = "sprint_id"
        case sprintLogs = "sprint_logs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }

    public init(
        boardId: UUID,
        columnId: UUID,
        prefix: String,
        cardNumber: Int,
        title: String,
        description: String? = nil,
        priority: CardPriority = .medium,
        status: CardStatus = .todo,
        position: Int,
        id: UUID = UUID(),
        now: Date = Date()
    ) {
        self.id = id
        self.boardId = boardId
        self.columnId = columnId
        self.prefix = prefix
        self.cardNumber = cardNumber
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.position = position
        dueDate = nil
        points = nil
        sprintId = nil
        sprintLogs = []
        createdAt = now
        updatedAt = now
        completedAt = status == .done ? now : nil
    }

    /// Mirrors kanban-rs `Card::update_status`: `completed_at` follows transitions into and out of `Done`.
    public mutating func updateStatus(_ newStatus: CardStatus, now: Date) {
        if newStatus == .done, status != .done {
            completedAt = now
        } else if newStatus != .done, status == .done {
            completedAt = nil
        }
        status = newStatus
        updatedAt = now
    }
}
