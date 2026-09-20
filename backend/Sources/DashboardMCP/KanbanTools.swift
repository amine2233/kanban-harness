import DashboardDomain
import DashboardService
import Foundation
import MCP

/// The MCP tool catalogue for boards and cards. Definitions are data; the
/// dispatcher below is the only place that knows the command protocols.
public enum KanbanTools {
    static func prop(_ type: String, _ description: String, enumValues: [String]? = nil) -> Value {
        var object: [String: Value] = ["type": .string(type), "description": .string(description)]
        if let enumValues { object["enum"] = .array(enumValues.map(Value.string)) }
        return .object(object)
    }

    static func schema(_ properties: [String: Value], required: [String]) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
            "additionalProperties": .bool(false),
        ])
    }

    static let project = prop("string", "Project name or id")
    static let board = prop("string", "Board name or id within the project")
    static let priorities = CardPriority.allCases.map(\.wireValue)
    static let statuses = CardStatus.allCases.map(\.wireValue)

    public static let all: [Tool] = [
        Tool(name: "list_projects", description: "List registered projects (folders holding a kanban workspace).", inputSchema: schema([:], required: [])),
        Tool(name: "list_boards", description: "List the boards of a project.", inputSchema: schema(["project": project], required: ["project"])),
        Tool(
            name: "create_board", description: "Create a board in a project. Seeds Backlog / To do / In progress / Done unless with_default_columns is false.",
            inputSchema: schema(["project": project, "name": prop("string", "Board name"), "with_default_columns": prop("boolean", "Seed the default columns (default true)")], required: ["project", "name"])
        ),
        Tool(name: "list_columns", description: "List the columns of a board in position order, with WIP limits and default statuses.", inputSchema: schema(["project": project, "board": board], required: ["project", "board"])),
        Tool(
            name: "list_cards", description: "List the cards of a board, optionally filtered by column and/or status.",
            inputSchema: schema([
                "project": project, "board": board,
                "column": prop("string", "Column name or id to filter on"),
                "status": prop("string", "Status to filter on", enumValues: statuses),
            ], required: ["project", "board"])
        ),
        Tool(
            name: "create_card", description: "Create a card (task) in a column of a board.",
            inputSchema: schema([
                "project": project, "board": board,
                "column": prop("string", "Column name or id; defaults to the board's first column"),
                "title": prop("string", "Card title"),
                "description": prop("string", "Longer description (markdown)"),
                "priority": prop("string", "Priority (default medium)", enumValues: priorities),
            ], required: ["project", "board", "title"])
        ),
        Tool(
            name: "update_card", description: "Change a card's fields. Omitted fields are kept; pass an empty string to clear description, 0 to clear points.",
            inputSchema: schema([
                "project": project, "board": board,
                "card": prop("string", "Card id, number (e.g. 12) or key (e.g. task-12)"),
                "title": prop("string", "New title"),
                "description": prop("string", "New description"),
                "priority": prop("string", "New priority", enumValues: priorities),
                "status": prop("string", "New status", enumValues: statuses),
                "points": prop("integer", "Story points"),
                "due_date": prop("string", "Due date as YYYY-MM-DD, or empty to clear"),
            ], required: ["project", "board", "card"])
        ),
        Tool(
            name: "move_card", description: "Move a card to another column of the same board (its status follows the column's rules).",
            inputSchema: schema(["project": project, "board": board, "card": prop("string", "Card id, number or key"), "column": prop("string", "Destination column name or id")], required: ["project", "board", "card", "column"])
        ),
        Tool(
            name: "delete_card", description: "Delete a card permanently.",
            inputSchema: schema(["project": project, "board": board, "card": prop("string", "Card id, number or key")], required: ["project", "board", "card"])
        ),
        Tool(
            name: "create_subtasks", description: "Break a card down: create child cards in the parent's column, linked to it.",
            inputSchema: schema([
                "project": project, "board": board, "card": prop("string", "Parent card id, number or key"),
                "subtasks": .object([
                    "type": .string("array"), "description": .string("Children to create, in order"),
                    "items": schema([
                        "title": prop("string", "Title"), "description": prop("string", "Description (markdown)"),
                        "priority": prop("string", "Priority (default: the parent's)", enumValues: priorities),
                        "points": prop("integer", "Story points"),
                    ], required: ["title"]),
                ]),
            ], required: ["project", "board", "card", "subtasks"])
        ),
        Tool(
            name: "list_card_children", description: "List a card's sub-tasks with their column and status.",
            inputSchema: schema(["project": project, "board": board, "card": prop("string", "Parent card id, number or key")], required: ["project", "board", "card"])
        ),
        Tool(
            name: "set_card_parent", description: "Make a card a sub-task of another card on the same board (one parent per card, no cycles).",
            inputSchema: schema(["project": project, "board": board, "card": prop("string", "Child card id, number or key"), "parent": prop("string", "Parent card id, number or key")], required: ["project", "board", "card", "parent"])
        ),
        Tool(
            name: "remove_card_parent", description: "Detach a sub-task from its parent.",
            inputSchema: schema(["project": project, "board": board, "card": prop("string", "Child card id, number or key")], required: ["project", "board", "card"])
        ),
    ]
}

/// Executes tool calls against the command protocols; never touches storage or transport.
public struct KanbanToolDispatcher: Sendable {
    let projects: any ProjectCommands
    let boards: any BoardCommands

    public init(projects: any ProjectCommands, boards: any BoardCommands) {
        self.projects = projects
        self.boards = boards
    }

    public func call(_ name: String, _ arguments: [String: Value]) async -> CallTool.Result {
        do {
            let value = try await dispatch(name, Arguments(arguments))
            let text = try Self.render(value)
            return CallTool.Result(content: [.text(text)], structuredContent: Optional.some(value), isError: false)
        } catch let error as ToolError {
            return .init(content: [.text(error.message)], isError: true)
        } catch let error as ServiceError {
            return .init(content: [.text(error.localizedDescription)], isError: true)
        } catch {
            return .init(content: [.text(String(describing: error))], isError: true)
        }
    }

    private func dispatch(_ name: String, _ args: Arguments) async throws -> Value {
        switch name {
        case "list_projects":
            return try Self.items(try await projects.list().map(ProjectView.init))
        case "list_boards":
            return try Self.items(try await boards.boards(args.projectRef()).map(BoardView.init))
        case "create_board":
            let board = try await boards.createBoard(args.projectRef(), name: try args.string("name"), withDefaultColumns: args.bool("with_default_columns") ?? true)
            return try Value(BoardView(board))
        case "list_columns":
            let (project, board) = try await resolveBoard(args)
            return try Self.items(try await boards.columns(project, boardId: board.id).map(ColumnView.init))
        case "list_cards":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            var cards = try await boards.cards(project, boardId: board.id)
            if let filter = args.optionalString("column") {
                let column = try Self.find(columns, filter, what: "column")
                cards = cards.filter { $0.columnId == column.id }
            }
            if let status = args.optionalString("status") {
                guard let wanted = CardStatus(wireValue: status) else { throw ToolError("unknown status '\(status)'") }
                cards = cards.filter { $0.status == wanted }
            }
            return try Self.items(cards.map { CardView($0, columns: columns) })
        case "create_card":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            let column: Column
            if let filter = args.optionalString("column") {
                column = try Self.find(columns, filter, what: "column")
            } else {
                guard let first = columns.first else { throw ToolError("board '\(board.name)' has no columns") }
                column = first
            }
            let priority = try args.optionalString("priority").map { raw -> CardPriority in
                guard let value = CardPriority(wireValue: raw) else { throw ToolError("unknown priority '\(raw)'") }
                return value
            } ?? .medium
            let card = try await boards.createCard(project, columnId: column.id, title: try args.string("title"), description: args.optionalString("description"), priority: priority, aiCost: nil, subtasks: [])
            return try Value(CardView(card, columns: columns))
        case "update_card":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            let card = try Self.findCard(try await boards.cards(project, boardId: board.id), try args.string("card"))
            var changes = CardChanges(title: args.optionalString("title"))
            if let description = args.optionalString("description") { changes.description = .some(description.isEmpty ? nil : description) }
            if let raw = args.optionalString("priority") {
                guard let value = CardPriority(wireValue: raw) else { throw ToolError("unknown priority '\(raw)'") }
                changes.priority = value
            }
            if let raw = args.optionalString("status") {
                guard let value = CardStatus(wireValue: raw) else { throw ToolError("unknown status '\(raw)'") }
                changes.status = value
            }
            if let points = args.int("points") { changes.points = .some(points == 0 ? nil : points) }
            if let raw = args.optionalString("due_date") { changes.dueDate = .some(try Self.parseDate(raw)) }
            let updated = try await boards.updateCard(project, boardId: board.id, cardId: card.id, changes: changes)
            return try Value(CardView(updated, columns: columns))
        case "move_card":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            let card = try Self.findCard(try await boards.cards(project, boardId: board.id), try args.string("card"))
            let column = try Self.find(columns, try args.string("column"), what: "column")
            let moved = try await boards.updateCard(project, boardId: board.id, cardId: card.id, changes: CardChanges(columnId: column.id))
            return try Value(CardView(moved, columns: columns))
        case "delete_card":
            let (project, board) = try await resolveBoard(args)
            let card = try Self.findCard(try await boards.cards(project, boardId: board.id), try args.string("card"))
            try await boards.deleteCard(project, boardId: board.id, cardId: card.id)
            return .object(["deleted": .string(card.id.uuidString.lowercased()), "key": .string("\(card.prefix)-\(card.cardNumber)")])
        case "create_subtasks":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            let parent = try Self.findCard(try await boards.cards(project, boardId: board.id), try args.string("card"))
            guard case let .array(items)? = args.values["subtasks"] else { throw ToolError("subtasks must be an array") }
            let specs = try items.map { item -> SubtaskSpec in
                let fields = Arguments(item.objectValue ?? [:])
                let priority = try fields.optionalString("priority").map { raw -> CardPriority in
                    guard let value = CardPriority(wireValue: raw) else { throw ToolError("unknown priority '\(raw)'") }
                    return value
                }
                return SubtaskSpec(title: try fields.string("title"), description: fields.optionalString("description"), priority: priority, points: fields.int("points"))
            }
            for spec in specs {
                let child = try await boards.createCard(project, columnId: parent.columnId, title: spec.title, description: spec.description, priority: spec.priority ?? parent.priority, aiCost: nil, subtasks: [])
                if let points = spec.points {
                    _ = try await boards.updateCard(project, boardId: board.id, cardId: child.id, changes: CardChanges(points: .some(points)))
                }
                _ = try await boards.setParent(project, boardId: board.id, cardId: child.id, parentId: parent.id)
            }
            return try Self.items(try await boards.children(project, boardId: board.id, cardId: parent.id).map { CardView($0, columns: columns) })
        case "list_card_children":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            let parent = try Self.findCard(try await boards.cards(project, boardId: board.id), try args.string("card"))
            return try Self.items(try await boards.children(project, boardId: board.id, cardId: parent.id).map { CardView($0, columns: columns) })
        case "set_card_parent", "remove_card_parent":
            let (project, board) = try await resolveBoard(args)
            let columns = try await boards.columns(project, boardId: board.id)
            let cards = try await boards.cards(project, boardId: board.id)
            let child = try Self.findCard(cards, try args.string("card"))
            let parent = name == "set_card_parent" ? try Self.findCard(cards, try args.string("parent")) : nil
            let updated = try await boards.setParent(project, boardId: board.id, cardId: child.id, parentId: parent?.id)
            return try Value(CardView(updated, columns: columns))
        default:
            throw ToolError("unknown tool '\(name)'")
        }
    }

    // MARK: Resolution helpers

    private func resolveBoard(_ args: Arguments) async throws -> (ProjectRef, Board) {
        let project = try args.projectRef()
        let board = try Self.find(try await boards.boards(project), try args.string("board"), what: "board")
        return (project, board)
    }

    static func find<T: Identifiable>(_ items: [T], _ reference: String, what: String) throws -> T where T.ID == UUID {
        if let id = UUID(uuidString: reference), let match = items.first(where: { $0.id == id }) { return match }
        let byName = items.filter { name(of: $0).caseInsensitiveCompare(reference) == .orderedSame }
        guard let match = byName.first else { throw ToolError("\(what) not found: '\(reference)'") }
        guard byName.count == 1 else { throw ToolError("\(what) '\(reference)' is ambiguous; use its id") }
        return match
    }

    private static func name<T>(of item: T) -> String {
        switch item {
        case let board as Board: board.name
        case let column as Column: column.name
        default: ""
        }
    }

    static func findCard(_ cards: [Card], _ reference: String) throws -> Card {
        if let id = UUID(uuidString: reference), let match = cards.first(where: { $0.id == id }) { return match }
        let number = Int(reference.split(separator: "-").last.map(String.init) ?? reference)
        if let number, let match = cards.first(where: { $0.cardNumber == number && (reference.contains("-") ? reference.lowercased().hasPrefix($0.prefix.lowercased()) : true) }) {
            return match
        }
        throw ToolError("card not found: '\(reference)'")
    }

    static func parseDate(_ raw: String) throws -> Date? {
        if raw.isEmpty { return nil }
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        if let date = try? style.parse(raw) { return date }
        if let date = try? style.parse(raw + "T00:00:00Z") { return date }
        throw ToolError("invalid due_date '\(raw)': use YYYY-MM-DD")
    }

    /// MCP requires `structuredContent` to be an object, so lists are wrapped.
    static func items<T: Codable>(_ list: [T]) throws -> Value {
        .object(["items": try Value(list), "count": .int(list.count)])
    }

    static func render(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Typed access to tool arguments.
struct Arguments {
    let values: [String: Value]
    init(_ values: [String: Value]) { self.values = values }

    func string(_ key: String) throws -> String {
        guard let value = optionalString(key), !value.isEmpty else { throw ToolError("missing argument '\(key)'") }
        return value
    }

    func optionalString(_ key: String) -> String? {
        switch values[key] {
        case let .string(s)?: s
        case let .int(i)?: String(i)
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? { values[key]?.boolValue }
    func int(_ key: String) -> Int? { values[key]?.intValue }

    func projectRef() throws -> ProjectRef { .parse(try string("project")) }
}

// MARK: - Views (what tools return)

struct ProjectView: Codable {
    let id: String, name: String, path: String, storage: String
    init(_ p: Project) { id = p.id.uuidString.lowercased(); name = p.name; path = p.path; storage = p.storage.rawValue }
}

struct BoardView: Codable {
    let id: String, name: String, description: String?, cardPrefix: String?, position: Int
    enum CodingKeys: String, CodingKey { case id, name, description, position; case cardPrefix = "card_prefix" }
    init(_ b: Board) { id = b.id.uuidString.lowercased(); name = b.name; description = b.description; cardPrefix = b.cardPrefix; position = b.position }
}

struct ColumnView: Codable {
    let id: String, name: String, position: Int, wipLimit: Int?, defaultStatus: String?
    enum CodingKeys: String, CodingKey { case id, name, position; case wipLimit = "wip_limit"; case defaultStatus = "default_status" }
    init(_ c: Column) { id = c.id.uuidString.lowercased(); name = c.name; position = c.position; wipLimit = c.wipLimit; defaultStatus = c.defaultStatus?.wireValue }
}

struct CardView: Codable {
    let id: String, key: String, title: String, description: String?, priority: String, status: String
    let column: String, columnId: String, position: Int, points: Int?, dueDate: String?
    enum CodingKeys: String, CodingKey {
        case id, key, title, description, priority, status, column, position, points
        case columnId = "column_id"
        case dueDate = "due_date"
    }
    init(_ c: Card, columns: [Column]) {
        id = c.id.uuidString.lowercased()
        key = "\(c.prefix)-\(c.cardNumber)"
        title = c.title
        description = c.description
        priority = c.priority.wireValue
        status = c.status.wireValue
        column = columns.first { $0.id == c.columnId }?.name ?? c.columnId.uuidString.lowercased()
        columnId = c.columnId.uuidString.lowercased()
        position = c.position
        points = c.points
        dueDate = c.dueDate.map { Date.ISO8601FormatStyle().format($0) }
    }
}
