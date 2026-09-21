import DashboardDomain
import DashboardPersistence
import DashboardPersistenceFluent
import DashboardPersistenceJSON
import DashboardService

/// The one place that maps a project's `StorageKind` to a concrete store.
/// Both stores hold the same `Workspace`, so switching is a data copy, not a migration.
public enum WorkspaceStores {
    public static func factory(pool: SQLiteDatabasePool) -> WorkspaceStoreFactory {
        WorkspaceStoreFactory { project in
            switch project.storage {
            case .json: KanbanJSONStore(path: project.dataFile)
            case .sqlite: SQLiteWorkspaceStore(path: project.dataFile, pool: pool)
            }
        }
    }
}
