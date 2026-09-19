import DashboardDomain
import DashboardPersistence
import FluentKit
import Foundation

/// Table mappings for the kanban workspace. Timestamps are stored as RFC 3339
/// text and UUIDs as text so a row round-trips exactly like the JSON store.
public final class BoardModel: Model, @unchecked Sendable {
    public static let schema = "boards"

    @ID(custom: .id, generatedBy: .user) public var id: UUID?
    @Field(key: "name") public var name: String
    @OptionalField(key: "description") public var description: String?
    @OptionalField(key: "card_prefix") public var cardPrefix: String?
    @OptionalField(key: "sprint_prefix") public var sprintPrefix: String?
    @Field(key: "task_list_view") public var taskListView: String
    @Field(key: "task_sort_field") public var taskSortField: String
    @Field(key: "task_sort_order") public var taskSortOrder: String
    @OptionalField(key: "sprint_duration_days") public var sprintDurationDays: Int?
    @OptionalField(key: "active_sprint_id") public var activeSprintId: UUID?
    @Field(key: "position") public var position: Int
    @Field(key: "next_sprint_number") public var nextSprintNumber: Int
    @Field(key: "sprint_name_used_count") public var sprintNameUsedCount: Int
    @Field(key: "sprint_names") public var sprintNames: String
    @Field(key: "created_at") public var createdAt: String
    @Field(key: "updated_at") public var updatedAt: String

    public init() {}

    convenience init(_ board: Board) throws {
        self.init()
        id = board.id
        name = board.name
        description = board.description
        cardPrefix = board.cardPrefix
        sprintPrefix = board.sprintPrefix
        taskListView = board.taskListView
        taskSortField = board.taskSortField
        taskSortOrder = board.taskSortOrder
        sprintDurationDays = board.sprintDurationDays
        activeSprintId = board.activeSprintId
        position = board.position
        nextSprintNumber = board.nextSprintNumber
        sprintNameUsedCount = board.sprintNameUsedCount
        sprintNames = try JSONText.encode(board.sprintNames)
        createdAt = RFC3339.format(board.createdAt)
        updatedAt = RFC3339.format(board.updatedAt)
    }

    func toDomain() throws -> Board {
        var board = Board(
            name: name,
            position: position,
            id: try Row.id(id),
            now: try Row.date(createdAt, "created_at")
        )
        board.description = description
        board.cardPrefix = cardPrefix
        board.sprintPrefix = sprintPrefix
        board.taskListView = taskListView
        board.taskSortField = taskSortField
        board.taskSortOrder = taskSortOrder
        board.sprintDurationDays = sprintDurationDays
        board.activeSprintId = activeSprintId
        board.nextSprintNumber = nextSprintNumber
        board.sprintNameUsedCount = sprintNameUsedCount
        board.sprintNames = try JSONText.decode(sprintNames)
        board.updatedAt = try Row.date(updatedAt, "updated_at")
        return board
    }
}

public final class ColumnModel: Model, @unchecked Sendable {
    public static let schema = "columns"

    @ID(custom: .id, generatedBy: .user) public var id: UUID?
    @Field(key: "board_id") public var boardId: UUID
    @Field(key: "name") public var name: String
    @Field(key: "position") public var position: Int
    @OptionalField(key: "wip_limit") public var wipLimit: Int?
    @OptionalField(key: "default_status") public var defaultStatus: String?
    @Field(key: "created_at") public var createdAt: String
    @Field(key: "updated_at") public var updatedAt: String

    public init() {}

    convenience init(_ column: Column) {
        self.init()
        id = column.id
        boardId = column.boardId
        name = column.name
        position = column.position
        wipLimit = column.wipLimit
        defaultStatus = column.defaultStatus?.rawValue
        createdAt = RFC3339.format(column.createdAt)
        updatedAt = RFC3339.format(column.updatedAt)
    }

    func toDomain() throws -> Column {
        var column = Column(
            boardId: boardId,
            name: name,
            position: position,
            wipLimit: wipLimit,
            defaultStatus: try defaultStatus.map { try Row.enumValue($0, "default_status") },
            id: try Row.id(id),
            now: try Row.date(createdAt, "created_at")
        )
        column.updatedAt = try Row.date(updatedAt, "updated_at")
        return column
    }
}

public final class CardModel: Model, @unchecked Sendable {
    public static let schema = "cards"

    @ID(custom: .id, generatedBy: .user) public var id: UUID?
    @Field(key: "board_id") public var boardId: UUID
    @Field(key: "column_id") public var columnId: UUID
    @Field(key: "prefix") public var prefix: String
    @Field(key: "card_number") public var cardNumber: Int
    @Field(key: "title") public var title: String
    @OptionalField(key: "description") public var description: String?
    @Field(key: "priority") public var priority: String
    @Field(key: "status") public var status: String
    @Field(key: "position") public var position: Int
    @OptionalField(key: "due_date") public var dueDate: String?
    @OptionalField(key: "points") public var points: Int?
    @OptionalField(key: "sprint_id") public var sprintId: UUID?
    @Field(key: "sprint_logs") public var sprintLogs: String
    @Field(key: "created_at") public var createdAt: String
    @Field(key: "updated_at") public var updatedAt: String
    @OptionalField(key: "completed_at") public var completedAt: String?

    public init() {}

    convenience init(_ card: Card) throws {
        self.init()
        id = card.id
        boardId = card.boardId
        columnId = card.columnId
        prefix = card.prefix
        cardNumber = card.cardNumber
        title = card.title
        description = card.description
        priority = card.priority.rawValue
        status = card.status.rawValue
        position = card.position
        dueDate = card.dueDate.map(RFC3339.format)
        points = card.points
        sprintId = card.sprintId
        sprintLogs = try JSONText.encode(card.sprintLogs)
        createdAt = RFC3339.format(card.createdAt)
        updatedAt = RFC3339.format(card.updatedAt)
        completedAt = card.completedAt.map(RFC3339.format)
    }

    func toDomain() throws -> Card {
        var card = Card(
            boardId: boardId,
            columnId: columnId,
            prefix: prefix,
            cardNumber: cardNumber,
            title: title,
            description: description,
            priority: try Row.enumValue(priority, "priority"),
            status: try Row.enumValue(status, "status"),
            position: position,
            id: try Row.id(id),
            now: try Row.date(createdAt, "created_at")
        )
        card.dueDate = try dueDate.map { try Row.date($0, "due_date") }
        card.points = points
        card.sprintId = sprintId
        card.sprintLogs = try JSONText.decode(sprintLogs)
        card.updatedAt = try Row.date(updatedAt, "updated_at")
        card.completedAt = try completedAt.map { try Row.date($0, "completed_at") }
        return card
    }
}

public final class PrefixModel: Model, @unchecked Sendable {
    public static let schema = "prefixes"

    @ID(custom: "name", generatedBy: .user) public var id: String?
    @Field(key: "card_counter") public var cardCounter: Int
    @Field(key: "sprint_counter") public var sprintCounter: Int

    public init() {}

    convenience init(_ prefix: Prefix) {
        self.init()
        id = prefix.name
        cardCounter = prefix.cardCounter
        sprintCounter = prefix.sprintCounter
    }

    func toDomain() throws -> Prefix {
        guard let id else { throw PersistenceError.corrupt(path: Self.schema, reason: "prefix without name") }
        return Prefix(name: id, cardCounter: cardCounter, sprintCounter: sprintCounter)
    }
}

/// Sections of the workspace this backend does not model (sprints, archives,
/// graph, anything newer), stored as JSON so they survive a JSON⇄SQLite switch.
public final class SectionModel: Model, @unchecked Sendable {
    public static let schema = "workspace_sections"

    @ID(custom: "key", generatedBy: .user) public var id: String?
    @Field(key: "json") public var json: String

    public init() {}

    convenience init(key: String, value: JSONValue) throws {
        self.init()
        id = key
        json = try JSONText.encode(value)
    }
}

public struct CreateWorkspaceSchema: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(BoardModel.schema)
            .id()
            .field("name", .string, .required)
            .field("description", .string)
            .field("card_prefix", .string)
            .field("sprint_prefix", .string)
            .field("task_list_view", .string, .required)
            .field("task_sort_field", .string, .required)
            .field("task_sort_order", .string, .required)
            .field("sprint_duration_days", .int)
            .field("active_sprint_id", .uuid)
            .field("position", .int, .required)
            .field("next_sprint_number", .int, .required)
            .field("sprint_name_used_count", .int, .required)
            .field("sprint_names", .string, .required)
            .field("created_at", .string, .required)
            .field("updated_at", .string, .required)
            .create()
        try await database.schema(ColumnModel.schema)
            .id()
            .field("board_id", .uuid, .required, .references(BoardModel.schema, .id, onDelete: .cascade))
            .field("name", .string, .required)
            .field("position", .int, .required)
            .field("wip_limit", .int)
            .field("default_status", .string)
            .field("created_at", .string, .required)
            .field("updated_at", .string, .required)
            .create()
        try await database.schema(CardModel.schema)
            .id()
            .field("board_id", .uuid, .required, .references(BoardModel.schema, .id, onDelete: .cascade))
            .field("column_id", .uuid, .required, .references(ColumnModel.schema, .id, onDelete: .cascade))
            .field("prefix", .string, .required)
            .field("card_number", .int, .required)
            .field("title", .string, .required)
            .field("description", .string)
            .field("priority", .string, .required)
            .field("status", .string, .required)
            .field("position", .int, .required)
            .field("due_date", .string)
            .field("points", .int)
            .field("sprint_id", .uuid)
            .field("sprint_logs", .string, .required)
            .field("created_at", .string, .required)
            .field("updated_at", .string, .required)
            .field("completed_at", .string)
            .create()
        try await database.schema(PrefixModel.schema)
            .field("name", .string, .identifier(auto: false))
            .field("card_counter", .int, .required)
            .field("sprint_counter", .int, .required)
            .create()
        try await database.schema(SectionModel.schema)
            .field("key", .string, .identifier(auto: false))
            .field("json", .string, .required)
            .create()
    }

    public func revert(on database: any Database) async throws {
        for schema in [SectionModel.schema, PrefixModel.schema, CardModel.schema, ColumnModel.schema, BoardModel.schema] {
            try await database.schema(schema).delete()
        }
    }
}

/// Row-level decoding helpers with precise corruption errors.
enum Row {
    static func id(_ id: UUID?) throws -> UUID {
        guard let id else { throw PersistenceError.corrupt(path: "sqlite", reason: "row without id") }
        return id
    }

    static func date(_ text: String, _ column: String) throws -> Date {
        guard let date = RFC3339.parse(text) else {
            throw PersistenceError.corrupt(path: "sqlite", reason: "\(column): invalid timestamp '\(text)'")
        }
        return date
    }

    static func enumValue<T: RawRepresentable>(_ raw: String, _ column: String) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: raw) else {
            throw PersistenceError.corrupt(path: "sqlite", reason: "\(column): unknown value '\(raw)'")
        }
        return value
    }
}

enum JSONText {
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        RFC3339.configure(encoder)
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ text: String) throws -> T {
        let decoder = JSONDecoder()
        RFC3339.configure(decoder)
        return try decoder.decode(T.self, from: Data(text.utf8))
    }
}
