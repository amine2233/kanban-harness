import Foundation
import Testing
@testable import DashboardDomain

@Suite struct CardLifecycleTests {
    let board = UUID()
    var todo: Column { Column(boardId: board, name: "TODO", position: 0, defaultStatus: .todo) }
    var doing: Column { Column(boardId: board, name: "Doing", position: 1, defaultStatus: .inProgress) }
    var done: Column { Column(boardId: board, name: "Done", position: 2, defaultStatus: .done) }
    var plain: Column { Column(boardId: board, name: "Plain", position: 3) }

    func card(in column: Column, status: CardStatus) -> Card {
        Card(boardId: board, columnId: column.id, prefix: "task", cardNumber: 1, title: "t", status: status, position: 0)
    }

    @Test func movingIntoCompletionColumnBecomesDone() {
        #expect(CardLifecycle.statusAfterMove(card: card(in: todo, status: .todo), to: done, from: todo) == .done)
        #expect(CardLifecycle.statusAfterMove(card: card(in: todo, status: .done), to: done, from: todo) == nil)
    }

    @Test func leavingCompletionColumnResetsDoneToTodoThenPromotes() {
        #expect(CardLifecycle.statusAfterMove(card: card(in: done, status: .done), to: doing, from: done) == .inProgress)
        #expect(CardLifecycle.statusAfterMove(card: card(in: done, status: .done), to: plain, from: done) == .todo)
    }

    @Test func todoCardIsPromotedByDestinationDefaultStatus() {
        #expect(CardLifecycle.statusAfterMove(card: card(in: todo, status: .todo), to: doing, from: todo) == .inProgress)
        #expect(CardLifecycle.statusAfterMove(card: card(in: todo, status: .todo), to: plain, from: todo) == nil)
    }

    @Test func nonTodoCardKeepsStatusOutsideCompletion() {
        #expect(CardLifecycle.statusAfterMove(card: card(in: doing, status: .blocked), to: todo, from: doing) == nil)
        #expect(CardLifecycle.statusAfterMove(card: card(in: doing, status: .inProgress), to: plain, from: doing) == nil)
    }

    @Test func updateStatusTracksCompletedAt() {
        var card = card(in: todo, status: .todo)
        let now = Date(timeIntervalSince1970: 100)
        card.updateStatus(.done, now: now)
        #expect(card.completedAt == now)
        card.updateStatus(.todo, now: now)
        #expect(card.completedAt == nil)
    }

    @Test func enumsMapBetweenPersistedAndWireTokens() {
        #expect(CardStatus.inProgress.rawValue == "InProgress")
        #expect(CardStatus.inProgress.wireValue == "in_progress")
        #expect(CardStatus(wireValue: "in_progress") == .inProgress)
        #expect(CardStatus(wireValue: "nope") == nil)
        #expect(CardPriority.critical.rawValue == "Critical")
        #expect(CardPriority(wireValue: "critical") == .critical)
    }
}
