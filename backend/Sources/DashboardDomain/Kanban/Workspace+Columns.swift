import Foundation

extension Workspace {
    @discardableResult
    public mutating func updateColumn(
        _ id: UUID,
        name: String? = nil,
        wipLimit: Int?? = nil,
        defaultStatus: CardStatus?? = nil,
        now: Date = Date()
    ) throws -> Column {
        let index = try columnIndex(id)
        var column = columns[index]
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DomainError.emptyColumnName }
            column.name = trimmed
        }
        if let wipLimit { column.wipLimit = wipLimit.map { max($0, 0) } }
        if let defaultStatus { column.defaultStatus = defaultStatus }
        column.updatedAt = now
        columns[index] = column
        return column
    }

    /// Removes a column and the cards in it. A board keeps at least one column.
    public mutating func deleteColumn(_ id: UUID) throws {
        let index = try columnIndex(id)
        let column = columns[index]
        guard columns(of: column.boardId).count > 1 else {
            throw DomainError.lastColumn(board: (try? board(column.boardId))?.name ?? column.boardId.uuidString)
        }
        let doomed = cards.filter { $0.columnId == id }.map(\.id)
        columns.remove(at: index)
        cards.removeAll { $0.columnId == id }
        for cardId in doomed {
            removeGraphEdges(mentioning: cardId)
        }
        compactColumnPositions(in: column.boardId)
    }

    @discardableResult
    public mutating func moveColumn(_ id: UUID, toPosition position: Int, now: Date = Date()) throws -> Column {
        let boardId = try column(id).boardId
        var ordered = columns(of: boardId)
        let from = ordered.firstIndex { $0.id == id }!
        let moving = ordered.remove(at: from)
        ordered.insert(moving, at: min(max(position, 0), ordered.count))
        for (position, column) in ordered.enumerated() where column.position != position {
            ordered[position].position = position
            ordered[position].updatedAt = now
        }
        columns.removeAll { $0.boardId == boardId }
        columns.append(contentsOf: ordered)
        return try column(id)
    }

    private func columnIndex(_ id: UUID) throws -> Int {
        guard let index = columns.firstIndex(where: { $0.id == id }) else { throw DomainError.columnNotFound(id) }
        return index
    }

    private mutating func compactColumnPositions(in boardId: UUID) {
        for (position, column) in columns(of: boardId).enumerated() {
            if let index = columns.firstIndex(where: { $0.id == column.id }), columns[index].position != position {
                columns[index].position = position
            }
        }
    }
}
