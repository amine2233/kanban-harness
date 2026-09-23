import CascadeKit
import DashboardPersistenceFluent
import DashboardService
import Foundation
import Testing
@testable import DashboardRuntime

@Suite(.serialized) struct RuntimeTests {
    func tempHome() throws -> String {
        let path = NSTemporaryDirectory() + "mvp-dashboard-runtime-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test func runtimeConfigDefaultsToTheHomeDependency() async throws {
        let home = try tempHome()
        let config = await withTestDependencies {
            $0.home = home
        } operation: {
            RuntimeConfig()
        }
        #expect(config.home == home)
        #expect(config.registryPath == home + "/projects.sqlite")
        #expect(config.settingsPath == home + "/settings.json")
        #expect(RuntimeConfig(home: "/explicit").home == "/explicit")
        #expect(RuntimeConfig(home: home, claudeExecutable: "/stub/claude").claudeExecutable == "/stub/claude")
        #expect(RuntimeConfig(home: home).claudeExecutable == (ProcessInfo.processInfo.environment["MVP_DASHBOARD_CLAUDE_BIN"] ?? "claude"))
    }

    @Test func homeKeyReadsEnvironmentThenLocalThenXDGThenHome() throws {
        #expect(HomeKey.defaultHome(environment: ["MVP_DASHBOARD_HOME": "/x"], currentDirectory: "/nowhere") == "/x")
        #expect(HomeKey.defaultHome(environment: ["XDG_CONFIG_HOME": "/cfg"], currentDirectory: "/nowhere") == "/cfg/kanban-harness")
        #expect(HomeKey.defaultHome(environment: ["HOME": "/me"], currentDirectory: "/nowhere") == "/me/.config/kanban-harness")
    }

    /// A folder with its own `.kanban-harness` keeps its own home; a sibling without
    /// one falls back to the user's.
    @Test func homeKeyPrefersALocalDirectoryOverTheGlobalOne() throws {
        let workspace = try tempHome()
        let local = workspace + "/" + HomeKey.localDirectoryName
        try FileManager.default.createDirectory(atPath: local, withIntermediateDirectories: true)

        #expect(HomeKey.defaultHome(environment: ["HOME": "/me"], currentDirectory: workspace) == local)
        #expect(HomeKey.defaultHome(environment: ["HOME": "/me"], currentDirectory: workspace + "/..") == "/me/.config/kanban-harness")
        #expect(
            HomeKey.defaultHome(environment: ["MVP_DASHBOARD_HOME": "/x"], currentDirectory: workspace) == "/x",
            "an explicit environment home still wins"
        )
    }

    @Test func registerWiresSingletonsAndServicesWork() async throws {
        let home = try tempHome()
        let container = CascadeKit.Application()
        try await DashboardRuntime.register(on: container, config: RuntimeConfig(home: home))

        #expect(container.make(WorkspacePoolKey.self) === container.make(WorkspacePoolKey.self))
        #expect(container.make(ProjectServiceKey.self) === container.make(ProjectServiceKey.self))
        #expect(FileManager.default.fileExists(atPath: home + "/projects.sqlite"))

        let projects = container.make(ProjectServiceKey.self)
        let project = try await projects.add(name: "Demo", path: home + "/demo", storage: .sqlite)
        #expect(FileManager.default.fileExists(atPath: project.dataFile))
        let settings = container.make(SettingsServiceKey.self)
        _ = try await settings.update(defaultStorage: .sqlite)
        #expect(FileManager.default.fileExists(atPath: home + "/settings.json"))
        await DashboardRuntime.shutdown(container)
        await DashboardRuntime.shutdown(container)
    }

    @Test func shutdownClosesResourcesAndAllowsReopening() async throws {
        let home = try tempHome()
        let container = CascadeKit.Application()
        try await DashboardRuntime.register(on: container, config: RuntimeConfig(home: home))
        let pool = container.make(WorkspacePoolKey.self)
        _ = try await pool.database(at: home + "/ws.sqlite")
        await DashboardRuntime.shutdown(container)

        let reopened = CascadeKit.Application()
        try await DashboardRuntime.register(on: reopened, config: RuntimeConfig(home: home))
        #expect(try await reopened.make(ProjectServiceKey.self).list().isEmpty)
        await DashboardRuntime.shutdown(reopened)
    }

    @Test func registerAcceptsAnExternalRegistryDatabase() async throws {
        let home = try tempHome()
        let external = try SQLiteDatabase.registry(path: home + "/external.sqlite")
        try await external.migrate()
        let container = CascadeKit.Application()
        try await DashboardRuntime.register(on: container, config: RuntimeConfig(home: home), registryDatabase: external.database)
        _ = try await container.make(ProjectServiceKey.self).add(name: "Ext", path: home + "/ext")
        #expect(FileManager.default.fileExists(atPath: home + "/external.sqlite"))
        #expect(!FileManager.default.fileExists(atPath: home + "/projects.sqlite"))
        await DashboardRuntime.shutdown(container)
        try await external.shutdown()
    }
}
