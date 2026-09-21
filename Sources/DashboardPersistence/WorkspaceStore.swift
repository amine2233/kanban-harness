import DashboardDomain

/// One kanban-rs workspace file. Implementations own the wire format.
public protocol WorkspaceStore: Sendable {
    /// The workspace, or an empty one when the file does not exist yet.
    func load() async throws -> Workspace
    func save(_ workspace: Workspace) async throws
}

public actor InMemoryWorkspaceStore: WorkspaceStore {
    private var workspace = Workspace()

    public init() {}

    public func load() async throws -> Workspace { workspace }

    public func save(_ workspace: Workspace) async throws {
        self.workspace = workspace
    }
}
