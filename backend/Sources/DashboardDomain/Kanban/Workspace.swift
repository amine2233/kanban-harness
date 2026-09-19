import Foundation

/// The `data` section of a kanban-rs file as one aggregate. Boards, columns,
/// cards and prefixes are modelled; every other key (sprints, archives, graph,
/// anything newer) is carried in `extra` so it round-trips untouched.
public struct Workspace: Equatable, Sendable {
    public var boards: [Board]
    public var columns: [Column]
    public var cards: [Card]
    public var prefixes: [Prefix]
    public var extra: [String: JSONValue]

    public static let defaultTemplateColumns: [(name: String, status: CardStatus)] = [
        ("TODO", .todo), ("Doing", .inProgress), ("Complete", .done),
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
        self.extra = extra
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
    public mutating func createBoard(name: String, id: UUID = UUID(), now: Date = Date()) -> Board {
        let board = Board(name: name, position: boards.count, id: id, now: now)
        boards.append(board)
        return board
    }

    /// A board seeded with kanban-rs' default template columns.
    @discardableResult
    public mutating func createBoardWithTemplateColumns(name: String, now: Date = Date()) -> Board {
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
        now: Date = Date()
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
        id: UUID = UUID(),
        now: Date = Date()
    ) throws -> Card {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyTitle }
        let column = try column(columnId)
        let board = try board(column.boardId)
        try checkWipLimit(column, adding: 1)
        let prefix = board.cardPrefix ?? Prefix.defaultCardPrefix
        let card = Card(
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
        cards.append(card)
        return card
    }

    @discardableResult
    public mutating func moveCard(_ id: UUID, toColumn destinationId: UUID, now: Date = Date()) throws -> Card {
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
        now: Date = Date()
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
        card.updatedAt = now
        cards[index] = card
        return card
    }

    public mutating func deleteCard(_ id: UUID) throws {
        let index = try cardIndex(id)
        let columnId = cards[index].columnId
        cards.remove(at: index)
        compactPositions(in: columnId)
        removeGraphEdges(mentioning: id)
    }

    // MARK: Internals

    private func cardIndex(_ id: UUID) throws -> Int {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { throw DomainError.cardNotFound(id) }
        return index
    }

    private func checkWipLimit(_ column: Column, adding: Int) throws {
        guard let limit = column.wipLimit else { return }
        if cards(in: column.id).count + adding > limit {
            throw DomainError.wipLimitExceeded(column: column.name, limit: limit)
        }
    }

    private mutating func allocateCardNumber(prefix: String) -> Int {
        let key = prefix.lowercased()
        if let index = prefixes.firstIndex(where: { $0.name == key }) {
            prefixes[index].cardCounter += 1
            return prefixes[index].cardCounter
        }
        prefixes.append(Prefix(name: key, cardCounter: 1))
        return 1
    }

    private mutating func compactPositions(in columnId: UUID) {
        let ordered = cards(in: columnId)
        for (position, card) in ordered.enumerated() {
            if let index = cards.firstIndex(where: { $0.id == card.id }), cards[index].position != position {
                cards[index].position = position
            }
        }
    }

    /// Drops every edge in `graph.{spawns,blocks,relates}.edges` that names the card.
    private mutating func removeGraphEdges(mentioning cardId: UUID) {
        guard var graph = extra["graph"]?.objectValue else { return }
        let needle = cardId.uuidString
        for (kind, value) in graph {
            guard var bucket = value.objectValue, let edges = bucket["edges"]?.arrayValue else { continue }
            bucket["edges"] = .array(edges.filter { !$0.containsString(needle) })
            graph[kind] = .object(bucket)
        }
        extra["graph"] = .object(graph)
    }
}
