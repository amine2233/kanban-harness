import DashboardDomain
import Foundation
import Testing
@testable import DashboardPersistenceConfig

@Suite
struct ConfigFileDatabaseConfigStoreTests {
    func path(_ name: String) throws -> String {
        let dir = NSTemporaryDirectory() + "mvp-dashboard-db-config-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/" + name
    }

    @Test
    func aMissingFileFallsBackToTheDefault() async throws {
        let store = try ConfigFileDatabaseConfigStore(path: path("config.yaml"), environment: [:])
        #expect(try await store.load() == DatabaseConfig())
    }

    @Test(arguments: [
        ("config.yaml", "database:\n  thread_pool_size: 4\n"),
        ("config.json", #"{"database": {"thread_pool_size": 4}}"#)
    ])
    func readsTheThreadPoolSizeInBothFormats(file: String, contents: String) async throws {
        let store = try ConfigFileDatabaseConfigStore(path: path(file), environment: [:])
        try contents.write(toFile: store.path, atomically: true, encoding: .utf8)
        #expect(try await store.load().threadPoolSize == 4)
    }

    @Test
    func leavesOtherSectionsAlone() async throws {
        let store = try ConfigFileDatabaseConfigStore(path: path("config.yaml"), environment: [:])
        try """
        ai:
          default_provider: claude
          provider_ids: [claude]
          providers:
            claude: { kind: anthropic, name: Claude, model: claude-sonnet-5 }
        database:
          thread_pool_size: 3
        """.write(toFile: store.path, atomically: true, encoding: .utf8)
        #expect(try await store.load().threadPoolSize == 3)
        #expect(try await ConfigFileAIConfigStore(path: store.path, environment: [:]).load()
            .defaultProviderId == "claude")
    }

    @Test
    func theEnvironmentOverridesTheFile() async throws {
        let store = try ConfigFileDatabaseConfigStore(
            path: path("config.yaml"),
            environment: ["MVP_DASHBOARD_DATABASE_THREAD_POOL_SIZE": "8"]
        )
        try "database:\n  thread_pool_size: 2\n".write(toFile: store.path, atomically: true, encoding: .utf8)
        #expect(try await store.load().threadPoolSize == 8)
    }

    @Test(arguments: [0, -4])
    func nonsenseSizesClampToOneThread(size: Int) async throws {
        let store = try ConfigFileDatabaseConfigStore(path: path("config.yaml"), environment: [:])
        try "database:\n  thread_pool_size: \(size)\n".write(
            toFile: store.path,
            atomically: true,
            encoding: .utf8
        )
        #expect(try await store.load().threadPoolSize == 1)
    }
}
