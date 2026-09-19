import Foundation
import Testing
@testable import DashboardDomain

@Suite struct WorkspaceTests {
    let now = Date(timeIntervalSince1970: 1_000)

    func seeded() -> (Workspace, Board, [Column]) {
        var workspace = Workspace()
        let board = workspace.createBoardWithTemplateColumns(name: "Demo", now: now)
        return (workspace, board, workspace.columns(of: board.id))
    }

    @Test func createBoardWithTemplateColumnsSeedsThreeOrderedColumns() {
        let (workspace, board, columns) = seeded()
        #expect(board.position == 0)
        #expect(columns.map(\.name) == ["TODO", "Doing", "Complete"])
        #expect(columns.map(\.position) == [0, 1, 2])
        #expect(columns.map(\.defaultStatus) == [.todo, .inProgress, .done])
        #expect(workspace.boards.count == 1)
    }

    @Test func createBoardAppendsPosition() {
        var workspace = Workspace()
        workspace.createBoard(name: "A")
        let second = workspace.createBoard(name: "B")
        #expect(second.position == 1)
    }

    @Test func createColumnOnUnknownBoardThrows() {
        var workspace = Workspace()
        let id = UUID()
        #expect(throws: DomainError.boardNotFound(id)) {
            try workspace.createColumn(boardId: id, name: "X")
        }
    }

    @Test func createCardAllocatesNumbersFromPrefixCounter() throws {
        var (workspace, _, columns) = seeded()
        let first = try workspace.createCard(columnId: columns[0].id, title: "One", now: now)
        let second = try workspace.createCard(columnId: columns[0].id, title: "Two", now: now)
        #expect(first.prefix == "task")
        #expect([first.cardNumber, second.cardNumber] == [1, 2] as [Int])
        #expect([first.position, second.position] == [0, 1] as [Int])
        #expect(workspace.prefixes == [Prefix(name: "task", cardCounter: 2)])
    }

    @Test func createCardContinuesExistingPrefixCounterCaseInsensitively() throws {
        var (workspace, board, columns) = seeded()
        workspace.boards[0].cardPrefix = "KAN"
        workspace.prefixes = [Prefix(name: "kan", cardCounter: 41)]
        let card = try workspace.createCard(columnId: columns[0].id, title: "x")
        #expect(card.prefix == "KAN")
        #expect(card.cardNumber == 42)
        #expect(card.boardId == board.id)
    }

    @Test func createCardTakesColumnDefaultStatusAndTrimsTitle() throws {
        var (workspace, _, columns) = seeded()
        let doing = try workspace.createCard(columnId: columns[1].id, title: "  Ship  ", now: now)
        #expect(doing.status == .inProgress)
        #expect(doing.title == "Ship")
        let done = try workspace.createCard(columnId: columns[2].id, title: "Old", now: now)
        #expect(done.status == .done)
        #expect(done.completedAt == now)
    }

    @Test func createCardWithBlankTitleThrows() {
        var (workspace, _, columns) = seeded()
        #expect(throws: DomainError.emptyTitle) {
            try workspace.createCard(columnId: columns[0].id, title: "   ")
        }
    }

    @Test func createCardRespectsWipLimit() throws {
        var (workspace, _, columns) = seeded()
        workspace.columns[1].wipLimit = 1
        try workspace.createCard(columnId: columns[1].id, title: "one")
        #expect(throws: DomainError.wipLimitExceeded(column: "Doing", limit: 1)) {
            try workspace.createCard(columnId: columns[1].id, title: "two")
        }
    }

    @Test func moveCardUpdatesColumnStatusAndCompactsOrigin() throws {
        var (workspace, _, columns) = seeded()
        let a = try workspace.createCard(columnId: columns[0].id, title: "a", now: now)
        let b = try workspace.createCard(columnId: columns[0].id, title: "b", now: now)
        let later = now.addingTimeInterval(60)

        let moved = try workspace.moveCard(a.id, toColumn: columns[2].id, now: later)
        #expect(moved.columnId == columns[2].id)
        #expect(moved.status == .done)
        #expect(moved.completedAt == later)
        #expect(moved.position == 0)
        #expect(try workspace.card(b.id).position == 0, "origin column is compacted")

        let back = try workspace.moveCard(a.id, toColumn: columns[1].id, now: later)
        #expect(back.status == .inProgress)
        #expect(back.completedAt == nil)
    }

    @Test func moveCardToSameColumnIsNoOp() throws {
        var (workspace, _, columns) = seeded()
        let card = try workspace.createCard(columnId: columns[0].id, title: "a", now: now)
        let same = try workspace.moveCard(card.id, toColumn: columns[0].id, now: now.addingTimeInterval(5))
        #expect(same == card)
    }

    @Test func moveCardAcrossBoardsIsRejected() throws {
        var (workspace, _, columns) = seeded()
        let other = workspace.createBoardWithTemplateColumns(name: "Other")
        let foreign = workspace.columns(of: other.id)[0]
        let card = try workspace.createCard(columnId: columns[0].id, title: "a")
        #expect(throws: DomainError.columnNotFound(foreign.id)) {
            try workspace.moveCard(card.id, toColumn: foreign.id)
        }
    }

    @Test func moveCardRespectsDestinationWipLimit() throws {
        var (workspace, _, columns) = seeded()
        workspace.columns[1].wipLimit = 0
        let card = try workspace.createCard(columnId: columns[0].id, title: "a")
        #expect(throws: DomainError.wipLimitExceeded(column: "Doing", limit: 0)) {
            try workspace.moveCard(card.id, toColumn: columns[1].id)
        }
    }

    @Test func updateCardChangesFieldsAndStatusCompletion() throws {
        var (workspace, _, columns) = seeded()
        let card = try workspace.createCard(columnId: columns[0].id, title: "a", now: now)
        let updated = try workspace.updateCard(
            card.id, title: "b", description: .some("d"), priority: .high, status: .done, now: now
        )
        #expect(updated.title == "b")
        #expect(updated.description == "d")
        #expect(updated.priority == .high)
        #expect(updated.completedAt == now)
        let cleared = try workspace.updateCard(card.id, description: .some(nil))
        #expect(cleared.description == nil)
        #expect(cleared.title == "b")
    }

    @Test func deleteCardCompactsColumnAndDropsGraphEdges() throws {
        var (workspace, _, columns) = seeded()
        let a = try workspace.createCard(columnId: columns[0].id, title: "a")
        let b = try workspace.createCard(columnId: columns[0].id, title: "b")
        let edge: JSONValue = .object(["from": .string(a.id.uuidString.lowercased()), "to": .string(b.id.uuidString.lowercased())])
        let other: JSONValue = .object(["from": .string("x"), "to": .string("y")])
        workspace.extra["graph"] = .object([
            "blocks": .object(["edges": .array([edge, other])]),
            "spawns": .object(["edges": .array([])]),
        ])

        try workspace.deleteCard(a.id)

        #expect(workspace.cards.map(\.id) == [b.id])
        #expect(try workspace.card(b.id).position == 0)
        #expect(workspace.extra["graph"]?.objectValue?["blocks"]?.objectValue?["edges"] == .array([other]))
        #expect(throws: DomainError.cardNotFound(a.id)) {
            try workspace.deleteCard(a.id)
        }
    }

    @Test func queriesReturnEntitiesSortedByPosition() throws {
        var (workspace, board, columns) = seeded()
        let first = try workspace.createCard(columnId: columns[0].id, title: "1")
        let second = try workspace.createCard(columnId: columns[1].id, title: "2")
        workspace.cards.swapAt(0, 1)
        #expect(workspace.cards(of: board.id).map(\.id) == [first.id, second.id])
        #expect(workspace.cards(in: columns[1].id).map(\.id) == [second.id])
        let missing = UUID()
        #expect(throws: DomainError.cardNotFound(missing)) {
            try workspace.card(missing)
        }
    }
}
