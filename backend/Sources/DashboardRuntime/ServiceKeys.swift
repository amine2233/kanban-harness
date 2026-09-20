import CascadeKit
import DashboardPersistence
import DashboardPersistenceFluent
import DashboardService
import FluentKit

/// cascade-kit service keys. Composition roots resolve these; nothing else
/// names a concrete store.
public enum RuntimeConfigKey: ServiceKey {
    public typealias Value = RuntimeConfig
}

public enum RegistryDatabaseKey: ServiceKey {
    public typealias Value = any Database
}

public enum ProjectStoreKey: ServiceKey {
    public typealias Value = any ProjectStore
}

public enum SettingsStoreKey: ServiceKey {
    public typealias Value = any SettingsStore
}

public enum WorkspacePoolKey: ServiceKey {
    public typealias Value = SQLiteDatabasePool
}

public enum WorkspaceStoreFactoryKey: ServiceKey {
    public typealias Value = WorkspaceStoreFactory
}

public enum ProjectServiceKey: ServiceKey {
    public typealias Value = ProjectService
}

public enum SettingsServiceKey: ServiceKey {
    public typealias Value = SettingsService
}

public enum ProjectCommandsKey: ServiceKey {
    public typealias Value = any ProjectCommands
}

public enum SettingsCommandsKey: ServiceKey {
    public typealias Value = any SettingsCommands
}

public enum ChangeBroadcasterKey: ServiceKey {
    public typealias Value = ChangeBroadcaster
}

public enum ShutdownHooksKey: ServiceKey {
    public typealias Value = ShutdownHooks
}
