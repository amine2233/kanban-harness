import DashboardDomain

/// Behavioural contract every store must satisfy. Backend test targets call
/// these so all backends are held to one spec.
public enum StoreContract {
    public struct Violation: Error, CustomStringConvertible {
        public let description: String
    }

    public static func sampleProject(_ name: String, _ dir: String) -> Project {
        // swiftlint:disable:next force_try
        try! Project(name: name, path: "/\(dir)")
    }

    public static func verify(_ store: any ProjectStore) async throws {
        let fresh = try await store.load()
        try require(fresh.isEmpty, "fresh store must be empty")
        let projects = [sampleProject("A", "a"), sampleProject("B", "b")]
        try await store.save(projects)
        let loaded = try await store.load()
        try require(loaded == projects, "save then load must round-trip")
        let fewer = [projects[1]]
        try await store.save(fewer)
        let replaced = try await store.load()
        try require(replaced == fewer, "save must replace, not append")
        try await store.save([])
        let cleared = try await store.load()
        try require(cleared.isEmpty, "saving empty must clear")
    }

    public static func verify(_ store: any WorkspaceStore) async throws {
        let fresh = try await store.load()
        try require(fresh == Workspace(), "fresh store must be an empty workspace")
        var workspace = Workspace()
        let board = workspace.createBoardWithTemplateColumns(name: "Demo")
        let column = workspace.columns(of: board.id)[0]
        try workspace.createCard(columnId: column.id, title: "Card", priority: .high)
        try workspace.createCard(
            columnId: column.id, title: "Drafted",
            aiCost: AICost(
                provider: "cc",
                model: "sonnet",
                inputTokens: 2,
                outputTokens: 400,
                costUSD: 0.03,
                estimated: true
            )
        )
        let parent = try workspace.createCard(columnId: column.id, title: "Parent")
        try workspace.createSubtasks(of: parent.id, [SubtaskSpec(title: "Child", points: 2)])
        try await store.save(workspace)
        let loaded = try await store.load()
        try require(loaded.spawns == workspace.spawns, "parent/child links must round-trip")
        try require(loaded.boards == workspace.boards, "boards must round-trip")
        try require(loaded.columns == workspace.columns, "columns must round-trip")
        try require(loaded.cards == workspace.cards, "cards must round-trip")
        try require(loaded.prefixes == workspace.prefixes, "prefixes must round-trip")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Violation(description: message) }
    }
}
