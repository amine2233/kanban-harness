import CascadeKit
import DashboardAI
import DashboardAIProviders
import DashboardDomain
import DashboardPersistenceConfig
import DashboardPersistenceFluent
import DashboardPersistenceJSON
import DashboardProviderHuggingFace
import DashboardProviderOpenRouter
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
            let database = try SQLiteDatabase.registry(
                path: config.registryPath,
                logger: DependencyValues.current.logger
            )
            try await database.migrate()
            await hooks.add { try? await database.shutdown() }
            container.register(RegistryDatabaseKey.self) { _ in database.database }
        }

        let databaseConfig = await (try? ConfigFileDatabaseConfigStore(path: config.configPath).load()) ??
            DatabaseConfig()
        let pool = SQLiteDatabasePool(
            logger: DependencyValues.current.logger,
            numberOfThreads: databaseConfig.threadPoolSize
        )
        await hooks.add { await pool.shutdownAll() }
        container.register(WorkspacePoolKey.self) { _ in pool }

        container.register(ProjectStoreKey.self) { resolver in
            FluentProjectStore(database: resolver.make(RegistryDatabaseKey.self))
        }
        container.register(SettingsStoreKey.self) { resolver in
            JSONSettingsStore(path: resolver.make(RuntimeConfigKey.self).settingsPath)
        }
        container.register(WorkspaceStoreFactoryKey.self) { resolver in
            WorkspaceStores.factory(pool: resolver.make(WorkspacePoolKey.self))
        }
        container.register(ChangeBroadcasterKey.self) { _ in ChangeBroadcaster() }
        container.register(ProjectServiceKey.self) { resolver in
            ProjectService(
                store: resolver.make(ProjectStoreKey.self),
                workspaces: resolver.make(WorkspaceStoreFactoryKey.self),
                changes: resolver.make(ChangeBroadcasterKey.self)
            )
        }
        container.register(SettingsServiceKey.self) { resolver in
            SettingsService(
                store: resolver.make(SettingsStoreKey.self),
                changes: resolver.make(ChangeBroadcasterKey.self)
            )
        }
        container.register(CredentialStoreKey.self) { resolver in
            FileCredentialStore(path: resolver.make(RuntimeConfigKey.self).credentialsPath)
        }
        container.register(AIConfigStoreKey.self) { resolver in
            ConfigFileAIConfigStore(
                path: resolver.make(RuntimeConfigKey.self).configPath,
                credentials: resolver.make(CredentialStoreKey.self)
            )
        }
        container.register(AIConfigCommandsKey.self) { resolver in
            AIConfigService(
                store: resolver.make(AIConfigStoreKey.self),
                changes: resolver.make(ChangeBroadcasterKey.self)
            )
        }
        container.register(ProjectCommandsKey.self) { resolver in
            LocalProjectCommands(
                projects: resolver.make(ProjectServiceKey.self),
                settings: resolver.make(SettingsServiceKey.self)
            )
        }
        container.register(SettingsCommandsKey.self) { resolver in resolver.make(SettingsServiceKey.self) }
        container
            .register(BoardCommandsKey.self) { resolver in
                LocalBoardCommands(projects: resolver.make(ProjectServiceKey.self))
            }
        container.register(AIProviderRegistryKey.self) { resolver in
            let runtime = resolver.make(RuntimeConfigKey.self)
            var registry = AIProviderRegistry.standard(
                claudeExecutable: runtime.claudeExecutable,
                disabled: runtime.disabledProviders
            )
            HuggingFaceProvider.register(in: &registry)
            OpenRouterProvider.register(in: &registry)
            return registry
        }
        container.register(SignInCommandsKey.self) { resolver in
            ProviderSignInService(
                aiConfig: resolver.make(AIConfigCommandsKey.self),
                credentials: resolver.make(CredentialStoreKey.self),
                registry: resolver.make(AIProviderRegistryKey.self),
                changes: resolver.make(ChangeBroadcasterKey.self)
            )
        }
        container.register(AssistantCommandsKey.self) { resolver in
            AssistantService(
                aiConfig: resolver.make(AIConfigCommandsKey.self),
                boards: resolver.make(BoardCommandsKey.self),
                registry: resolver.make(AIProviderRegistryKey.self),
                signIn: resolver.make(SignInCommandsKey.self)
            )
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
