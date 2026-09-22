import Foundation

/// How the SQLite databases are opened. Read from the dashboard config file's
/// `database:` section, so a deployment can tune it without a rebuild.
public struct DatabaseConfig: Sendable, Equatable {
    public static let defaultThreadPoolSize = 2

    /// Blocking-IO threads backing one database file.
    public var threadPoolSize: Int

    public init(threadPoolSize: Int = Self.defaultThreadPoolSize) {
        self.threadPoolSize = max(1, threadPoolSize)
    }
}
