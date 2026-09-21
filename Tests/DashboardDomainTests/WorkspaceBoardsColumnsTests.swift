import Foundation
import Testing
@testable import DashboardDomain

@Suite struct WorkspaceBoardsColumnsTests {
    let now = Date(timeIntervalSince1970: 2_000)

    func seeded() throws -> (Workspace, Board, [Column]) {
        var workspace = Workspace()
        let board = workspace.createBoardWithTemplateColumns(name: "Demo", now: now)
        let columns = workspace.columns(of: board.id)
        try workspace.createCard(columnId: columns[0].id, title: "a", now: now)
        try workspace.createCard(columnId: columns[2].id, title: "b", priority: .high, now: now)
        return (workspace, board, columns)
    }

    // MARK: Boards

    @Test func updateBoardRenamesTrimsAndClearsPrefix() throws {
        var (workspace, board, _) = try seeded()
        let updated = try workspace.updateBoard(board.id, name: "  Renamed ", description: .some("d"), cardPrefix: .some("KAN"), now: now)
        #expect(updated.name == "Renamed")
        #expect(updated.description == "d")
        #expect(updated.cardPrefix == "KAN")
        let cleared = try workspace.updateBoard(board.id, cardPrefix: .some("  "))
        #expect(cleared.cardPrefix == nil)
        #expect(throws: DomainError.emptyBoardName) {
            try workspace.updateBoard(board.id, name: " ")
        }
    }

    @Test func deleteBoardCascadesColumnsCardsSprintsAndEdges() throws {
        var (workspace, board, _) = try seeded()
        let other = workspace.createBoardWithTemplateColumns(name: "Other", now: now)
        let cardId = workspace.cards[0].id
        workspace.extra["sprints"] = .array([
            .object(["id": .string("s1"), "board_id": .string(board.id.uuidString.lowercased())]),
            .object(["id": .string("s2"), "board_id": .string(other.id.uuidString.lowercased())]),
        ])
        workspace.extra["graph"] = .object(["blocks": .object(["edges": .array([.object(["from": .string(cardId.uuidString.lowercased())])])])])

        try workspace.deleteBoard(board.id)

        #expect(workspace.boards.map(\.name) == ["Other"])
        #expect(workspace.boards[0].position == 0, "positions are compacted")
        #expect(workspace.columns.allSatisfy { $0.boardId == other.id })
        #expect(workspace.cards.isEmpty)
        #expect(workspace.extra["sprints"]?.arrayValue?.count == 1)
        #expect(workspace.extra["graph"]?.objectValue?["blocks"]?.objectValue?["edges"] == .array([]))
        #expect(throws: DomainError.boardNotFound(board.id)) {
            try workspace.deleteBoard(board.id)
        }
    }

    @Test func moveBoardReordersAndClamps() throws {
        var workspace = Workspace()
        let a = workspace.createBoard(name: "A", now: now)
        let b = workspace.createBoard(name: "B", now: now)
        let c = workspace.createBoard(name: "C", now: now)
        try workspace.moveBoard(c.id, toPosition: 0)
        #expect(workspace.boards.sorted { $0.position < $1.position }.map(\.name) == ["C", "A", "B"])
        try workspace.moveBoard(a.id, toPosition: 99)
        #expect(workspace.boards.sorted { $0.position < $1.position }.map(\.name) == ["C", "B", "A"])
        #expect(workspace.boards.map(\.position).sorted() == [0, 1, 2])
        _ = b
    }

    @Test func cloneBoardDeepCopiesWithFreshIdsAndNumbers() throws {
        var (workspace, board, columns) = try seeded()
        workspace.columns[2].wipLimit = 3
        let clone = try workspace.cloneBoard(board.id, now: now)
        #expect(clone.name == "Demo copy")
        #expect(clone.position == 1)
        #expect(clone.id != board.id)
        let clonedColumns = workspace.columns(of: clone.id)
        #expect(clonedColumns.map(\.name) == columns.map(\.name))
        #expect(clonedColumns.map(\.defaultStatus) == columns.map(\.defaultStatus))
        #expect(clonedColumns[2].wipLimit == 3)
        #expect(Set(clonedColumns.map(\.id)).isDisjoint(with: columns.map(\.id)))
        let clonedCards = workspace.cards(of: clone.id)
        #expect(clonedCards.map(\.title) == ["a", "b"])
        #expect(clonedCards.map(\.cardNumber) == [3, 4] as [Int])
        #expect(clonedCards[1].priority == .high)
        #expect(clonedCards[1].columnId == clonedColumns[2].id)
        #expect(workspace.cards(of: board.id).count == 2, "source untouched")
        let named = try workspace.cloneBoard(board.id, name: "Explicit")
        #expect(named.name == "Explicit")
    }

    // MARK: Columns

    @Test func updateColumnChangesNameWipAndDefaultStatus() throws {
        var (workspace, _, columns) = try seeded()
        let updated = try workspace.updateColumn(columns[0].id, name: " Backlog ", wipLimit: .some(2), defaultStatus: .some(.blocked), now: now)
        #expect(updated.name == "Backlog")
        #expect(updated.wipLimit == 2)
        #expect(updated.defaultStatus == .blocked)
        let cleared = try workspace.updateColumn(columns[0].id, wipLimit: .some(nil), defaultStatus: .some(nil))
        #expect(cleared.wipLimit == nil)
        #expect(cleared.defaultStatus == nil)
        #expect(throws: DomainError.emptyColumnName) {
            try workspace.updateColumn(columns[0].id, name: "")
        }
    }

    @Test func deleteColumnRemovesItsCardsAndCompacts() throws {
        var (workspace, board, columns) = try seeded()
        try workspace.deleteColumn(columns[0].id)
        #expect(workspace.columns(of: board.id).map(\.name) == ["To do", "In progress", "Done"])
        #expect(workspace.columns(of: board.id).map(\.position) == [0, 1, 2] as [Int])
        #expect(workspace.cards.map(\.title) == ["b"])
    }

    @Test func deleteLastColumnIsRefused() throws {
        var workspace = Workspace()
        let board = workspace.createBoard(name: "Solo")
        let only = try workspace.createColumn(boardId: board.id, name: "Only")
        #expect(throws: DomainError.lastColumn(board: "Solo")) {
            try workspace.deleteColumn(only.id)
        }
    }

    @Test func moveColumnReordersWithinBoardOnly() throws {
        var (workspace, board, columns) = try seeded()
        let other = workspace.createBoardWithTemplateColumns(name: "Other")
        try workspace.moveColumn(columns[2].id, toPosition: 0)
        #expect(workspace.columns(of: board.id).map(\.name) == ["In progress", "Backlog", "To do", "Done"])
        #expect(workspace.columns(of: other.id).map(\.name) == ["Backlog", "To do", "In progress", "Done"])
    }

    // MARK: Cards across boards

    @Test func moveCardToBoardRenumbersAndTakesFirstColumn() throws {
        var (workspace, board, _) = try seeded()
        let other = workspace.createBoardWithTemplateColumns(name: "Other", now: now)
        workspace.boards[1].cardPrefix = "OTH"
        let card = workspace.cards[1]
        let moved = try workspace.moveCardToBoard(card.id, boardId: other.id, now: now)
        #expect(moved.boardId == other.id)
        #expect(moved.columnId == workspace.columns(of: other.id)[0].id)
        #expect(moved.prefix == "OTH")
        #expect(moved.cardNumber == 1)
        #expect(moved.status == .inProgress, "same status rules as an in-board move")
        #expect(workspace.cards(of: board.id).map(\.title) == ["a"])
        let explicit = try workspace.moveCardToBoard(workspace.cards[0].id, boardId: other.id, columnId: workspace.columns(of: other.id)[3].id, now: now)
        #expect(explicit.status == .done)
    }

    @Test func moveCardToBoardRejectsForeignColumnAndUnknownBoard() throws {
        var (workspace, _, columns) = try seeded()
        let other = workspace.createBoardWithTemplateColumns(name: "Other")
        let card = workspace.cards[0]
        #expect(throws: DomainError.columnNotFound(columns[0].id)) {
            try workspace.moveCardToBoard(card.id, boardId: other.id, columnId: columns[0].id)
        }
        let ghost = UUID()
        #expect(throws: DomainError.boardNotFound(ghost)) {
            try workspace.moveCardToBoard(card.id, boardId: ghost)
        }
    }

    @Test func updateCardSetsDueDateAndPoints() throws {
        var (workspace, _, _) = try seeded()
        let due = Date(timeIntervalSince1970: 3_000)
        let updated = try workspace.updateCard(workspace.cards[0].id, dueDate: .some(due), points: .some(5))
        #expect(updated.dueDate == due)
        #expect(updated.points == 5)
        let cleared = try workspace.updateCard(workspace.cards[0].id, dueDate: .some(nil), points: .some(nil))
        #expect(cleared.dueDate == nil)
        #expect(cleared.points == nil)
    }
}
