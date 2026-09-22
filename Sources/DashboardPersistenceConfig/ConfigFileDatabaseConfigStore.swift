import Configuration
import DashboardDomain
import DashboardPersistence
import Foundation
import SystemPackage

/// Database settings in the dashboard's config file (`config.json` or
/// `config.yaml`), read through swift-configuration so an environment variable
/// overrides the file — `MVP_DASHBOARD_DATABASE_THREAD_POOL_SIZE=4`.
///
/// Layout:
///
///     database:
///       thread_pool_size: 2
///
/// Read-only: nothing in the dashboard writes this section back, so the file
/// stays hand-edited and every other top-level section is left alone.
public struct ConfigFileDatabaseConfigStore {
    public static let envPrefix = "mvp_dashboard"

    public let path: String
    private let environment: [String: String]

    public init(
        path: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.path = path
        self.environment = environment
    }

    public var isYAML: Bool {
        ["yaml", "yml"].contains((path as NSString).pathExtension.lowercased())
    }

    public func load() async throws -> DatabaseConfig {
        let database = try await reader().scoped(to: "database")
        return DatabaseConfig(
            threadPoolSize: database.int(forKey: "thread_pool_size") ?? DatabaseConfig.defaultThreadPoolSize
        )
    }

    private func reader() async throws -> ConfigReader {
        let env = EnvironmentVariablesProvider(environmentVariables: environment).prefixKeys(with: ConfigKey([Self.envPrefix]))
        let file: any ConfigProvider
        do {
            if isYAML {
                file = try await FileProvider<YAMLSnapshot>(filePath: FilePath(path), allowMissing: true)
            } else {
                file = try await FileProvider<JSONSnapshot>(filePath: FilePath(path), allowMissing: true)
            }
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
        return ConfigReader(providers: [env, file])
    }
}
