import Foundation

/// Pure status rules ported from kanban-rs `card_lifecycle::target_status_for_column_move`.
public enum CardLifecycle {
    /// The status a card takes when moved to `destination`, or `nil` when it keeps its status.
    public static func statusAfterMove(
        card: Card,
        to destination: Column,
        from origin: Column?
    ) -> CardStatus? {
        if destination.isCompletion {
            return card.status == .done ? nil : .done
        }
        let afterCompletionRules: CardStatus =
            (origin?.isCompletion == true && card.status == .done) ? .todo : card.status
        let promoted = afterCompletionRules == .todo ? destination.defaultStatus : nil
        if let promoted, promoted != card.status {
            return promoted
        }
        return afterCompletionRules == card.status ? nil : afterCompletionRules
    }
}
