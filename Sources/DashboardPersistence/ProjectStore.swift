import DashboardDomain

/// Backends only load and save the list of projects; invariants live in `ProjectRegistry`.
public protocol ProjectStore: Sendable {
    /// Every persisted project; an absent store yields an empty list.
    func load() async throws -> [Project]
    /// Replaces the persisted list atomically.
    func save(_ projects: [Project]) async throws
}

public actor ProjectStoreInMemory: ProjectStore {
    private var projects: [Project] = []

    public init() {}

    public func load() async throws -> [Project] {
        projects
    }

    public func save(_ projects: [Project]) async throws {
        self.projects = projects
    }
}
