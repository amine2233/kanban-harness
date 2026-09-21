import DashboardDomain
import DashboardPersistence

/// Builds the store for a project's workspace file. Injected by the
/// composition root so the service layer never names a file format.
public struct WorkspaceStoreFactory: Sendable {
    public let make: @Sendable (Project) -> any WorkspaceStore

    public init(make: @escaping @Sendable (Project) -> any WorkspaceStore) {
        self.make = make
    }
}
