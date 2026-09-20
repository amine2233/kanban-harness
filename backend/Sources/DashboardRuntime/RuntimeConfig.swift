import CascadeKit
import DashboardService
import Foundation

/// Where the process keeps its own data. Defaults to the `\.home` dependency.
public struct RuntimeConfig: Sendable, Equatable {
    public static let registryFileName = "projects.sqlite"
    public static let settingsFileName = "settings.json"
    public static let configFileNames = ["config.yaml", "config.yml", "config.json"]

    public var home: String
    /// The Claude Code executable used by `claude_code` providers (`MVP_DASHBOARD_CLAUDE_BIN`, else `claude` on PATH).
    public var claudeExecutable: String

    public init(home: String? = nil, claudeExecutable: String? = nil) {
        self.home = home ?? DependencyValues.current.home
        self.claudeExecutable = claudeExecutable ?? ProcessInfo.processInfo.environment["MVP_DASHBOARD_CLAUDE_BIN"] ?? "claude"
    }

    public var registryPath: String {
        (home as NSString).appendingPathComponent(Self.registryFileName)
    }

    public var settingsPath: String {
        (home as NSString).appendingPathComponent(Self.settingsFileName)
    }

    /// `config.yaml`/`config.yml` when one exists, otherwise `config.json` (created on first save).
    public var configPath: String {
        let candidates = Self.configFileNames.map { (home as NSString).appendingPathComponent($0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[candidates.count - 1]
    }
}
