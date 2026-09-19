import Foundation

extension Workspace {
    @discardableResult
    public mutating func updateBoard(
        _ id: UUID,
        name: String? = nil,
        description: String?? = nil,
        cardPrefix: String?? = nil,
        now: Date = Date()
    ) throws -> Board {
        let index = try boardIndex(id)
        var board = boards[index]
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DomainError.emptyBoardName }
            board.name = trimmed
        }
        if let description { board.description = description }
        if let cardPrefix { board.cardPrefix = cardPrefix?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        board.updatedAt = now
        boards[index] = board
        return board
    }

    /// Removes the board with everything it owns: columns, cards (and their
    /// graph edges) and, in the unmodelled sections, its sprints.
    public mutating func deleteBoard(_ id: UUID) throws {
        let index = try boardIndex(id)
        let doomedCards = cards.filter { $0.boardId == id }.map(\.id)
        boards.remove(at: index)
        columns.removeAll { $0.boardId == id }
        cards.removeAll { $0.boardId == id }
        for cardId in doomedCards {
            removeGraphEdges(mentioning: cardId)
        }
        if let sprints = extra["sprints"]?.arrayValue {
            let needle = id.uuidString
            extra["sprints"] = .array(sprints.filter { sprint in
                guard case let .string(boardId)? = sprint.objectValue?["board_id"] else { return true }
                return boardId.caseInsensitiveCompare(needle) != .orderedSame
            })
        }
        compactBoardPositions()
    }

    /// Reorders boards so `id` ends up at `position` (clamped), others shift.
    @discardableResult
    public mutating func moveBoard(_ id: UUID, toPosition position: Int, now: Date = Date()) throws -> Board {
        _ = try boardIndex(id)
        var ordered = boards.sorted { $0.position < $1.position }
        let from = ordered.firstIndex { $0.id == id }!
        let moving = ordered.remove(at: from)
        ordered.insert(moving, at: min(max(position, 0), ordered.count))
        for (position, board) in ordered.enumerated() where board.position != position {
            ordered[position].position = position
            ordered[position].updatedAt = now
        }
        boards = ordered
        return try board(id)
    }

    /// Deep copy: columns keep order, WIP limits and default statuses; cards keep
    /// their column, order, status and priority but get fresh ids and numbers.
    @discardableResult
    public mutating func cloneBoard(_ id: UUID, name: String? = nil, now: Date = Date()) throws -> Board {
        let source = try board(id)
        var copy = createBoard(name: name ?? "\(source.name) copy", now: now)
        copy.description = source.description
        copy.cardPrefix = source.cardPrefix
        copy.sprintPrefix = source.sprintPrefix
        copy.taskListView = source.taskListView
        copy.taskSortField = source.taskSortField
        copy.taskSortOrder = source.taskSortOrder
        copy.sprintDurationDays = source.sprintDurationDays
        boards[boards.count - 1] = copy

        var columnMap: [UUID: UUID] = [:]
        for column in columns(of: source.id) {
            let cloned = Column(
                boardId: copy.id, name: column.name, position: column.position,
                wipLimit: column.wipLimit, defaultStatus: column.defaultStatus, now: now
            )
            columnMap[column.id] = cloned.id
            columns.append(cloned)
        }
        let prefix = copy.cardPrefix ?? Prefix.defaultCardPrefix
        for card in cards(of: source.id) {
            guard let columnId = columnMap[card.columnId] else { continue }
            var cloned = Card(
                boardId: copy.id, columnId: columnId, prefix: prefix,
                cardNumber: allocateCardNumber(prefix: prefix), title: card.title,
                description: card.description, priority: card.priority, status: card.status,
                position: card.position, now: now
            )
            cloned.dueDate = card.dueDate
            cloned.points = card.points
            cloned.completedAt = card.completedAt
            cards.append(cloned)
        }
        return copy
    }

    private func boardIndex(_ id: UUID) throws -> Int {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { throw DomainError.boardNotFound(id) }
        return index
    }

    private mutating func compactBoardPositions() {
        let ordered = boards.sorted { $0.position < $1.position }
        for (position, board) in ordered.enumerated() {
            if let index = boards.firstIndex(where: { $0.id == board.id }), boards[index].position != position {
                boards[index].position = position
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
