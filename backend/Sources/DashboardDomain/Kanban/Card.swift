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

/// What drafting a card with AI cost; the first entry of a card's cost history.
/// `costUSD` nil = unknown (no pricing configured), `estimated` = computed from tokens.
public struct AICost: Codable, Hashable, Sendable {
    public var provider: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUSD: Double?
    public var estimated: Bool

    enum CodingKeys: String, CodingKey {
        case provider, model, estimated
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUSD = "cost_usd"
    }

    public init(provider: String, model: String, inputTokens: Int? = nil, outputTokens: Int? = nil, costUSD: Double? = nil, estimated: Bool = false) {
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.estimated = estimated
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decode(String.self, forKey: .provider)
        model = try c.decode(String.self, forKey: .model)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
        estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
    }
}

public struct Card: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var boardId: UUID
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
    /// Extra key, absent unless the card was drafted with AI; kanban-rs ignores it.
    public var aiCost: AICost?
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
        case aiCost = "ai_cost"
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
        now: Date = .timestamp()
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
        aiCost = nil
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
