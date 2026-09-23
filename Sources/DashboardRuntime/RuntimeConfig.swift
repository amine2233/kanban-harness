import CascadeKit
import DashboardService
import Foundation

/// Where the process keeps its own data. Defaults to the `\.home` dependency.
public struct RuntimeConfig: Sendable, Equatable {
    public static let registryFileName = "projects.sqlite"
    /// Written by the daemon once it knows its port, removed when it stops.
    public static let daemonPortFileName = "daemon.port"
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

    /// Provider secrets (API keys, OAuth tokens), kept apart from the shareable config file.
    public var credentialsPath: String {
        (home as NSString).appendingPathComponent("credentials.json")
    }

    /// `config.yaml`/`config.yml` when one exists, otherwise `config.json` (created on first save).
    public var daemonPortPath: String {
        (home as NSString).appendingPathComponent(Self.daemonPortFileName)
    }

    /// Where every other surface reaches this home's daemon, or `nil` when none is
    /// running. The port is per home rather than fixed, so two homes never share a
    /// daemon — which is what keeps several workspaces, and parallel tests,
    /// independent. Loopback only: `URLSession` cannot dial a unix socket, and the
    /// daemon must never leave this machine.
    public var daemonURL: URL? {
        if let forced = ProcessInfo.processInfo.environment["MVP_DASHBOARD_DAEMON_PORT"].flatMap(Int.init) {
            return URL(string: "http://127.0.0.1:\(forced)")
        }
        guard let text = try? String(contentsOfFile: daemonPortPath, encoding: .utf8),
              let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    /// Seconds without a request after which the daemon stops, so a command that
    /// started one does not leave it behind for ever.
    public var daemonIdleTimeout: Duration {
        .seconds(ProcessInfo.processInfo.environment["MVP_DASHBOARD_DAEMON_IDLE"].flatMap(Int.init) ?? 300)
    }

    public var configPath: String {
        let candidates = Self.configFileNames.map { (home as NSString).appendingPathComponent($0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[candidates.count - 1]
    }
}
