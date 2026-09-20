import CascadeKit
import DashboardAI
import DashboardAIProviders
import DashboardPersistenceConfig
import DashboardPersistenceFluent
import DashboardPersistenceJSON
import DashboardService
import FluentKit
import Foundation

/// The composition root shared by the CLI and the server: registers every
/// store and service on a cascade-kit container with singleton lifetime.
public enum DashboardRuntime {
    /// `registryDatabase` lets a host that already owns a Fluent database
    /// (Vapor's `app.db`) share it; otherwise the runtime opens and migrates
    /// `projects.sqlite` itself and closes it on `shutdown`.
    public static func register(
        on container: any Container,
        config: RuntimeConfig,
        registryDatabase: (any Database)? = nil
    ) async throws {
        try FileManager.default.createDirectory(atPath: config.home, withIntermediateDirectories: true)
        let hooks = ShutdownHooks()
        container.register(ShutdownHooksKey.self) { _ in hooks }
        container.storage.set(HooksSlot.self, to: hooks)
        container.register(RuntimeConfigKey.self) { _ in config }

        if let registryDatabase {
            container.register(RegistryDatabaseKey.self) { _ in registryDatabase }
        } else {
            let database = try SQLiteDatabase.registry(path: config.registryPath, logger: DependencyValues.current.logger)
            try await database.migrate()
            await hooks.add { try? await database.shutdown() }
            container.register(RegistryDatabaseKey.self) { _ in database.database }
        }

        let pool = SQLiteDatabasePool(logger: DependencyValues.current.logger)
        await hooks.add { await pool.shutdownAll() }
        container.register(WorkspacePoolKey.self) { _ in pool }

        container.register(ProjectStoreKey.self) { c in
            FluentProjectStore(database: c.make(RegistryDatabaseKey.self))
        }
        container.register(SettingsStoreKey.self) { c in
            JSONSettingsStore(path: c.make(RuntimeConfigKey.self).settingsPath)
        }
        container.register(WorkspaceStoreFactoryKey.self) { c in
            WorkspaceStores.factory(pool: c.make(WorkspacePoolKey.self))
        }
        container.register(ChangeBroadcasterKey.self) { _ in ChangeBroadcaster() }
        container.register(ProjectServiceKey.self) { c in
            ProjectService(
                store: c.make(ProjectStoreKey.self),
                workspaces: c.make(WorkspaceStoreFactoryKey.self),
                changes: c.make(ChangeBroadcasterKey.self)
            )
        }
        container.register(SettingsServiceKey.self) { c in
            SettingsService(store: c.make(SettingsStoreKey.self), changes: c.make(ChangeBroadcasterKey.self))
        }
        container.register(AIConfigStoreKey.self) { c in
            ConfigFileAIConfigStore(path: c.make(RuntimeConfigKey.self).configPath)
        }
        container.register(AIConfigCommandsKey.self) { c in
            AIConfigService(store: c.make(AIConfigStoreKey.self), changes: c.make(ChangeBroadcasterKey.self))
        }
        container.register(ProjectCommandsKey.self) { c in
            LocalProjectCommands(projects: c.make(ProjectServiceKey.self), settings: c.make(SettingsServiceKey.self))
        }
        container.register(SettingsCommandsKey.self) { c in c.make(SettingsServiceKey.self) }
        container.register(BoardCommandsKey.self) { c in LocalBoardCommands(projects: c.make(ProjectServiceKey.self)) }
        container.register(AIProviderRegistryKey.self) { _ in AIProviderRegistry.standard }
        container.register(AssistantCommandsKey.self) { c in
            AssistantService(aiConfig: c.make(AIConfigCommandsKey.self), boards: c.make(BoardCommandsKey.self), registry: c.make(AIProviderRegistryKey.self))
        }
    }

    /// Runs the async shutdown hooks (workspace pool, then the registry
    /// database if the runtime opened it), then the container's own. Safe to call twice.
    public static func shutdown(_ container: any Container) async {
        if let hooks = hooks(in: container) {
            await hooks.drain()
        }
        container.storage.shutdownAll()
    }

    private static func hooks(in container: any Container) -> ShutdownHooks? {
        var current: (any Container)? = container
        while let scope = current {
            if let hooks = scope.storage.get(HooksSlot.self) { return hooks }
            current = scope.parent
        }
        return nil
    }

    /// The hooks are also stored under a plain storage key so `shutdown` can
    /// look them up without triggering cascade-kit's missing-factory fatalError.
    private struct HooksSlot: StorageKey {
        typealias Value = ShutdownHooks
    }

}
