import DashboardDomain
import DashboardPersistence
import FluentKit
import FluentSQLiteDriver
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
        self.id = board.id
        self.name = board.name
        self.description = board.description
        self.cardPrefix = board.cardPrefix
        self.sprintPrefix = board.sprintPrefix
        self.taskListView = board.taskListView
        self.taskSortField = board.taskSortField
        self.taskSortOrder = board.taskSortOrder
        self.sprintDurationDays = board.sprintDurationDays
        self.activeSprintId = board.activeSprintId
        self.position = board.position
        self.nextSprintNumber = board.nextSprintNumber
        self.sprintNameUsedCount = board.sprintNameUsedCount
        self.sprintNames = try JSONText.encode(board.sprintNames)
        self.createdAt = RFC3339.format(board.createdAt)
        self.updatedAt = RFC3339.format(board.updatedAt)
    }

    func toDomain() throws -> Board {
        var board = try Board(
            name: name,
            position: position,
            id: Row.id(id),
            now: Row.date(createdAt, "created_at")
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
        self.id = column.id
        self.boardId = column.boardId
        self.name = column.name
        self.position = column.position
        self.wipLimit = column.wipLimit
        self.defaultStatus = column.defaultStatus?.rawValue
        self.createdAt = RFC3339.format(column.createdAt)
        self.updatedAt = RFC3339.format(column.updatedAt)
    }

    func toDomain() throws -> Column {
        var column = try Column(
            boardId: boardId,
            name: name,
            position: position,
            wipLimit: wipLimit,
            defaultStatus: defaultStatus.map { try Row.enumValue($0, "default_status") },
            id: Row.id(id),
            now: Row.date(createdAt, "created_at")
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
    @OptionalField(key: "ai_cost") public var aiCost: String?
    @Field(key: "created_at") public var createdAt: String
    @Field(key: "updated_at") public var updatedAt: String
    @OptionalField(key: "completed_at") public var completedAt: String?

    public init() {}

    convenience init(_ card: Card) throws {
        self.init()
        self.id = card.id
        self.boardId = card.boardId
        self.columnId = card.columnId
        self.prefix = card.prefix
        self.cardNumber = card.cardNumber
        self.title = card.title
        self.description = card.description
        self.priority = card.priority.rawValue
        self.status = card.status.rawValue
        self.position = card.position
        self.dueDate = card.dueDate.map(RFC3339.format)
        self.points = card.points
        self.sprintId = card.sprintId
        self.sprintLogs = try JSONText.encode(card.sprintLogs)
        self.aiCost = try card.aiCost.map(JSONText.encode)
        self.createdAt = RFC3339.format(card.createdAt)
        self.updatedAt = RFC3339.format(card.updatedAt)
        self.completedAt = card.completedAt.map(RFC3339.format)
    }

    func toDomain() throws -> Card {
        var card = try Card(
            boardId: boardId,
            columnId: columnId,
            prefix: prefix,
            cardNumber: cardNumber,
            title: title,
            description: description,
            priority: Row.enumValue(priority, "priority"),
            status: Row.enumValue(status, "status"),
            position: position,
            id: Row.id(id),
            now: Row.date(createdAt, "created_at")
        )
        card.dueDate = try dueDate.map { try Row.date($0, "due_date") }
        card.points = points
        card.sprintId = sprintId
        card.sprintLogs = try JSONText.decode(sprintLogs)
        card.aiCost = try aiCost.map { try JSONText.decode($0) }
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
        self.id = prefix.name
        self.cardCounter = prefix.cardCounter
        self.sprintCounter = prefix.sprintCounter
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
        self.id = key
        self.json = try JSONText.encode(value)
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
        for schema in [
            SectionModel.schema,
            PrefixModel.schema,
            CardModel.schema,
            ColumnModel.schema,
            BoardModel.schema
        ] {
            try await database.schema(schema).delete()
        }
    }
}

/// Cards remember what their AI draft cost (KAN: cost tracking, step 1).
public struct AddCardAICost: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        // Files created by an early build already carry the column without the migration row.
        if try await hasColumn(database) { return }
        try await database.schema(CardModel.schema).field("ai_cost", .string).update()
    }

    private func hasColumn(_ database: any Database) async throws -> Bool {
        guard let sql = database as? any SQLDatabase else { return false }

        let rows = try await sql.raw("PRAGMA table_info(\(unsafeRaw: CardModel.schema))").all()
        return try rows.contains { try $0.decode(column: "name", as: String.self) == "ai_cost" }
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(CardModel.schema).deleteField("ai_cost").update()
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

    static func enumValue<T: RawRepresentable>(_ raw: String, _ column: String) throws -> T
        where T.RawValue == String {
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
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ text: String) throws -> T {
        let decoder = JSONDecoder()
        RFC3339.configure(decoder)
        return try decoder.decode(T.self, from: Data(text.utf8))
    }
}
