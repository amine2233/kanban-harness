import DashboardRuntime
import Foundation

public struct ServerConfig: Sendable {
    public var runtime: RuntimeConfig
    /// Built frontend to serve alongside the API (SPA fallback to index.html).
    public var staticDir: String?
    /// Extra browser origins allowed to call the API, on top of `settings.json`.
    public var corsOrigins: [String]

    public init(
        home: String,
        staticDir: String? = nil,
        corsOrigins: [String] = [],
        claudeExecutable: String? = nil
    ) {
        self.runtime = RuntimeConfig(home: home, claudeExecutable: claudeExecutable)
        self.staticDir = staticDir
        self.corsOrigins = corsOrigins
    }

    public var home: String {
        runtime.home
    }

    public var registryPath: String {
        runtime.registryPath
    }

    public var settingsPath: String {
        runtime.settingsPath
    }
}
