import Foundation

/// The `data` section of a kanban-rs file as one aggregate. Boards, columns,
/// cards, prefixes and the parent/child graph (`graph.spawns`) are modelled;
/// every other key (sprints, archives, other graph kinds, anything newer) is
/// carried in `extra` so it round-trips untouched.
public struct Workspace: Equatable, Sendable {
    public var boards: [Board]
    public var columns: [Column]
    public var cards: [Card]
    public var prefixes: [Prefix]
    /// Parent → child links, including archived ones (kept as history like kanban-rs does).
    public var spawns: [SpawnsEdge]
    private var otherExtra: [String: JSONValue]

    /// The unmodelled sections, with `graph.spawns` rebuilt from `spawns` so
    /// stores keep reading and writing one dictionary.
    public var extra: [String: JSONValue] {
        get {
            var extra = otherExtra
            var graph = extra["graph"]?.objectValue ?? [:]
            graph["spawns"] = .object(["edges": .array(spawns.map(\.json))])
            extra["graph"] = .object(graph)
            return extra
        }
        set {
            (otherExtra, spawns) = Self.split(newValue)
        }
    }

    public static let defaultTemplateColumns: [(name: String, status: CardStatus?)] = [
        ("Backlog", nil), ("To do", .todo), ("In progress", .inProgress), ("Done", .done),
    ]

    public init(
        boards: [Board] = [],
        columns: [Column] = [],
        cards: [Card] = [],
        prefixes: [Prefix] = [],
        extra: [String: JSONValue] = [:]
    ) {
        self.boards = boards
        self.columns = columns
        self.cards = cards
        self.prefixes = prefixes
        (otherExtra, spawns) = Self.split(extra)
    }

    private static func split(_ extra: [String: JSONValue]) -> ([String: JSONValue], [SpawnsEdge]) {
        var other = extra
        var graph = extra["graph"]?.objectValue ?? [:]
        let edges = (graph.removeValue(forKey: "spawns")?.objectValue?["edges"]?.arrayValue ?? []).compactMap(SpawnsEdge.init(json:))
        if extra["graph"] != nil { other["graph"] = .object(graph) }
        return (other, edges)
    }

    // MARK: Queries

    public func board(_ id: UUID) throws -> Board {
        guard let board = boards.first(where: { $0.id == id }) else { throw DomainError.boardNotFound(id) }
        return board
    }

    public func column(_ id: UUID) throws -> Column {
        guard let column = columns.first(where: { $0.id == id }) else { throw DomainError.columnNotFound(id) }
        return column
    }

    public func card(_ id: UUID) throws -> Card {
        guard let card = cards.first(where: { $0.id == id }) else { throw DomainError.cardNotFound(id) }
        return card
    }

    public func columns(of boardId: UUID) -> [Column] {
        columns.filter { $0.boardId == boardId }.sorted { $0.position < $1.position }
    }

    public func cards(of boardId: UUID) -> [Card] {
        cards.filter { $0.boardId == boardId }.sorted {
            ($0.position, $0.cardNumber) < ($1.position, $1.cardNumber)
        }
    }

    public func cards(in columnId: UUID) -> [Card] {
        cards.filter { $0.columnId == columnId }.sorted { $0.position < $1.position }
    }

    // MARK: Commands

    @discardableResult
    public mutating func createBoard(name: String, id: UUID = UUID(), now: Date = .timestamp()) -> Board {
        let board = Board(name: name.trimmingCharacters(in: .whitespacesAndNewlines), position: boards.count, id: id, now: now)
        boards.append(board)
        return board
    }

    /// A board seeded with kanban-rs' default template columns.
    @discardableResult
    public mutating func createBoardWithTemplateColumns(name: String, now: Date = .timestamp()) -> Board {
        let board = createBoard(name: name, now: now)
        for template in Self.defaultTemplateColumns {
            columns.append(
                Column(
                    boardId: board.id,
                    name: template.name,
                    position: columns(of: board.id).count,
                    defaultStatus: template.status,
                    now: now
                )
            )
        }
        return board
    }

    @discardableResult
    public mutating func createColumn(
        boardId: UUID,
        name: String,
        wipLimit: Int? = nil,
        defaultStatus: CardStatus? = nil,
        id: UUID = UUID(),
        now: Date = .timestamp()
    ) throws -> Column {
        _ = try board(boardId)
        let column = Column(
            boardId: boardId,
            name: name,
            position: columns(of: boardId).count,
            wipLimit: wipLimit,
            defaultStatus: defaultStatus,
            id: id,
            now: now
        )
        columns.append(column)
        return column
    }

    @discardableResult
    public mutating func createCard(
        columnId: UUID,
        title: String,
        description: String? = nil,
        priority: CardPriority = .medium,
        aiCost: AICost? = nil,
        id: UUID = UUID(),
        now: Date = .timestamp()
    ) throws -> Card {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyTitle }
        let column = try column(columnId)
        let board = try board(column.boardId)
        try checkWipLimit(column, adding: 1)
        let prefix = board.cardPrefix ?? Prefix.defaultCardPrefix
        var card = Card(
            boardId: board.id,
            columnId: column.id,
            prefix: prefix,
            cardNumber: allocateCardNumber(prefix: prefix),
            title: trimmed,
            description: description,
            priority: priority,
            status: column.defaultStatus ?? .todo,
            position: cards(in: column.id).count,
            id: id,
            now: now
        )
        card.aiCost = aiCost
        cards.append(card)
        return card
    }

    @discardableResult
    public mutating func moveCard(_ id: UUID, toColumn destinationId: UUID, now: Date = .timestamp()) throws -> Card {
        let index = try cardIndex(id)
        let destination = try column(destinationId)
        var card = cards[index]
        guard destination.boardId == card.boardId else { throw DomainError.columnNotFound(destinationId) }
        if card.columnId == destination.id { return card }
        try checkWipLimit(destination, adding: 1)
        let origin = columns.first { $0.id == card.columnId }
        let originId = card.columnId
        card.columnId = destination.id
        card.position = cards(in: destination.id).count
        card.updatedAt = now
        if let status = CardLifecycle.statusAfterMove(card: card, to: destination, from: origin) {
            card.updateStatus(status, now: now)
        }
        cards[index] = card
        compactPositions(in: originId)
        return card
    }

    @discardableResult
    public mutating func updateCard(
        _ id: UUID,
        title: String? = nil,
        description: String?? = nil,
        priority: CardPriority? = nil,
        status: CardStatus? = nil,
        dueDate: Date?? = nil,
        points: Int?? = nil,
        now: Date = .timestamp()
    ) throws -> Card {
        let index = try cardIndex(id)
        var card = cards[index]
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DomainError.emptyTitle }
            card.title = trimmed
        }
        if let description { card.description = description }
        if let priority { card.priority = priority }
        if let status { card.updateStatus(status, now: now) }
        if let dueDate { card.dueDate = dueDate }
        if let points { card.points = points }
        card.updatedAt = now
        cards[index] = card
        return card
    }

    /// Moves a card to another board: it lands in `columnId` (default: the
    /// board's first column), gets a number from that board's prefix and
    /// drops its sprint binding, which is board-scoped.
    @discardableResult
    public mutating func moveCardToBoard(
        _ id: UUID,
        boardId destinationBoardId: UUID,
        columnId: UUID? = nil,
        now: Date = .timestamp()
    ) throws -> Card {
        let index = try cardIndex(id)
        var card = cards[index]
        let board = try board(destinationBoardId)
        guard board.id != card.boardId else {
            return try columnId.map { try moveCard(id, toColumn: $0, now: now) } ?? card
        }
        let destination: Column
        if let columnId {
            destination = try column(columnId)
            guard destination.boardId == board.id else { throw DomainError.columnNotFound(columnId) }
        } else {
            guard let first = columns(of: board.id).first else { throw DomainError.lastColumn(board: board.name) }
            destination = first
        }
        try checkWipLimit(destination, adding: 1)
        let originColumnId = card.columnId
        let prefix = board.cardPrefix ?? Prefix.defaultCardPrefix
        card.boardId = board.id
        card.columnId = destination.id
        card.prefix = prefix
        card.cardNumber = allocateCardNumber(prefix: prefix)
        card.position = cards(in: destination.id).count
        card.sprintId = nil
        card.updatedAt = now
        if let status = CardLifecycle.statusAfterMove(card: card, to: destination, from: nil) {
            card.updateStatus(status, now: now)
        }
        cards[index] = card
        compactPositions(in: originColumnId)
        removeGraphEdges(mentioning: id, now: now)
        return card
    }

    public mutating func deleteCard(_ id: UUID, now: Date = .timestamp()) throws {
        let index = try cardIndex(id)
        let columnId = cards[index].columnId
        cards.remove(at: index)
        compactPositions(in: columnId)
        removeGraphEdges(mentioning: id, now: now)
    }

    // MARK: Internals

    private func cardIndex(_ id: UUID) throws -> Int {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { throw DomainError.cardNotFound(id) }
        return index
    }

    func checkWipLimit(_ column: Column, adding: Int) throws {
        guard let limit = column.wipLimit else { return }
        if cards(in: column.id).count + adding > limit {
            throw DomainError.wipLimitExceeded(column: column.name, limit: limit)
        }
    }

    mutating func allocateCardNumber(prefix: String) -> Int {
        let key = prefix.lowercased()
        if let index = prefixes.firstIndex(where: { $0.name == key }) {
            prefixes[index].cardCounter += 1
            return prefixes[index].cardCounter
        }
        prefixes.append(Prefix(name: key, cardCounter: 1))
        return 1
    }

    mutating func compactPositions(in columnId: UUID) {
        let ordered = cards(in: columnId)
        for (position, card) in ordered.enumerated() {
            if let index = cards.firstIndex(where: { $0.id == card.id }), cards[index].position != position {
                cards[index].position = position
            }
        }
    }

    /// Archives the card's parent/child links and drops it from the other
    /// graph kinds (`blocks`, `relates`), which are not modelled.
    mutating func removeGraphEdges(mentioning cardId: UUID, now: Date) {
        archiveSpawns(now: now) { $0.source == cardId || $0.target == cardId }
        guard var graph = otherExtra["graph"]?.objectValue else { return }
        let needle = cardId.uuidString
        for (kind, value) in graph {
            guard var bucket = value.objectValue, let edges = bucket["edges"]?.arrayValue else { continue }
            bucket["edges"] = .array(edges.filter { !$0.containsString(needle) })
            graph[kind] = .object(bucket)
        }
        otherExtra["graph"] = .object(graph)
    }
}
