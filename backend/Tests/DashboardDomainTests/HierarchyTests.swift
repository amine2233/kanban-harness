import Foundation
import Testing
@testable import DashboardDomain

@Suite struct HierarchyTests {
    func board() -> (Workspace, Board, Column) {
        var workspace = Workspace()
        let board = workspace.createBoardWithTemplateColumns(name: "B")
        return (workspace, board, workspace.columns(of: board.id)[0])
    }

    @Test func attachDetachAndProgress() throws {
        var (workspace, board, column) = board()
        let parent = try workspace.createCard(columnId: column.id, title: "Parent")
        let a = try workspace.createCard(columnId: column.id, title: "A")
        let b = try workspace.createCard(columnId: column.id, title: "B")
        try workspace.attach(a.id, to: parent.id)
        try workspace.attach(b.id, to: parent.id)
        #expect(workspace.children(of: parent.id).map(\.title) == ["A", "B"])
        #expect(workspace.parent(of: a.id) == parent.id)
        #expect(workspace.progress(of: parent.id) == CardProgress(total: 2, done: 0))
        let done = workspace.columns(of: board.id)[3]
        try workspace.moveCard(a.id, toColumn: done.id)
        #expect(workspace.progress(of: parent.id) == CardProgress(total: 2, done: 1))
        try workspace.detach(b.id)
        #expect(workspace.children(of: parent.id).map(\.title) == ["A"])
        #expect(workspace.spawns.count == 2, "a detached edge is archived, not dropped")
        #expect(workspace.spawns.filter(\.isActive).count == 1)
        try workspace.attach(b.id, to: parent.id)
        #expect(workspace.progress(of: parent.id).total == 2)
    }

    @Test func rulesOneParentSameBoardNoCycles() throws {
        var (workspace, _, column) = board()
        let other = workspace.createBoardWithTemplateColumns(name: "Other")
        let elsewhere = try workspace.createCard(columnId: workspace.columns(of: other.id)[0].id, title: "Elsewhere")
        let parent = try workspace.createCard(columnId: column.id, title: "P")
        let child = try workspace.createCard(columnId: column.id, title: "C")
        let grandchild = try workspace.createCard(columnId: column.id, title: "G")
        try workspace.attach(child.id, to: parent.id)
        try workspace.attach(grandchild.id, to: child.id)
        #expect(workspace.ancestors(of: grandchild.id) == [child.id, parent.id])
        #expect(throws: DomainError.selfRelation) { try workspace.attach(parent.id, to: parent.id) }
        #expect(throws: DomainError.crossBoardRelation) { try workspace.attach(elsewhere.id, to: parent.id) }
        #expect(throws: DomainError.alreadyHasParent(child.id)) { try workspace.attach(child.id, to: grandchild.id) }
        #expect(throws: DomainError.relationCycle) { try workspace.attach(parent.id, to: grandchild.id) }
        #expect(throws: DomainError.cardNotFound(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)) {
            try workspace.attach(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, to: parent.id)
        }
        try workspace.attach(child.id, to: parent.id)
        #expect(workspace.spawns.filter(\.isActive).count == 2, "re-attaching to the same parent is a no-op")
    }

    @Test func deletingOrMovingAwayArchivesTheLinks() throws {
        var (workspace, _, column) = board()
        let other = workspace.createBoardWithTemplateColumns(name: "Other")
        let parent = try workspace.createCard(columnId: column.id, title: "P")
        let a = try workspace.createCard(columnId: column.id, title: "A")
        let b = try workspace.createCard(columnId: column.id, title: "B")
        try workspace.attach(a.id, to: parent.id)
        try workspace.attach(b.id, to: parent.id)
        try workspace.moveCardToBoard(a.id, boardId: other.id)
        #expect(workspace.parent(of: a.id) == nil)
        try workspace.deleteCard(parent.id)
        #expect(workspace.parent(of: b.id) == nil)
        #expect(workspace.spawns.allSatisfy { !$0.isActive })
    }

    @Test func subtasksAreCreatedInTheParentsColumnAtomically() throws {
        var (workspace, _, column) = board()
        let parent = try workspace.createCard(columnId: column.id, title: "P", priority: .high)
        let created = try workspace.createSubtasks(of: parent.id, [
            SubtaskSpec(title: "One", points: 3),
            SubtaskSpec(title: "Two", description: "d", priority: .low),
        ])
        #expect(created.map(\.title) == ["One", "Two"])
        #expect(created[0].points == 3 && created[0].priority == .high, "priority defaults to the parent's")
        #expect(created[1].priority == .low && created[1].description == "d")
        #expect(created.allSatisfy { $0.columnId == column.id })
        #expect(workspace.children(of: parent.id).map(\.cardNumber) == [2, 3])

        let before = workspace
        #expect(throws: DomainError.emptyTitle) {
            try workspace.createSubtasks(of: parent.id, [SubtaskSpec(title: "Three"), SubtaskSpec(title: "  ")])
        }
        #expect(workspace == before, "nothing is created when one sub-task is invalid")

        try workspace.updateColumn(column.id, wipLimit: .some(4))
        #expect(throws: DomainError.wipLimitExceeded(column: "Backlog", limit: 4)) {
            try workspace.createSubtasks(of: parent.id, [SubtaskSpec(title: "x"), SubtaskSpec(title: "y")])
        }
    }

    @Test func spawnsRoundTripThroughExtraWithOtherGraphKindsUntouched() throws {
        let parent = UUID(), child = UUID()
        let extra: [String: JSONValue] = ["graph": .object([
            "blocks": .object(["edges": .array([.object(["source": .string(parent.uuidString.lowercased()), "target": .string(child.uuidString.lowercased())])])]),
            "spawns": .object(["edges": .array([.object([
                "source": .string(parent.uuidString.lowercased()), "target": .string(child.uuidString.lowercased()),
                "created_at": .string("2026-05-24T17:19:59.858221763Z"), "archived_at": .null,
            ])])]),
        ])]
        let workspace = Workspace(extra: extra)
        #expect(workspace.spawns == [SpawnsEdge(source: parent, target: child, createdAt: "2026-05-24T17:19:59.858221763Z")])
        #expect(workspace.extra == extra, "the timestamp string is preserved to the nanosecond")
        #expect(workspace.extra["graph"]?.objectValue?["blocks"] == extra["graph"]?.objectValue?["blocks"])
        #expect(Workspace().extra["graph"]?.objectValue?["spawns"] == .object(["edges": .array([])]))
    }
}
