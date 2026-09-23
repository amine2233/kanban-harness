import DashboardRuntime
import Foundation

public struct ServerConfig: Sendable {
    public var runtime: RuntimeConfig
    /// Built frontend to serve alongside the API (SPA fallback to index.html).
    public var staticDir: String?
    /// Extra browser origins allowed to call the API, on top of `settings.json`.
    public var corsOrigins: [String]
    /// The origin a browser reaches this dashboard at (`MVP_DASHBOARD_PUBLIC_URL`),
    /// which is what the OAuth redirect URI and the post-sign-in redirect are built
    /// from. Unset, the request's `Host` is used and only a loopback one is accepted.
    public var publicURL: URL?

    public init(
        home: String,
        staticDir: String? = nil,
        corsOrigins: [String] = [],
        publicURL: URL? = nil,
        claudeExecutable: String? = nil
    ) {
        runtime = RuntimeConfig(home: home, claudeExecutable: claudeExecutable)
        self.staticDir = staticDir
        self.corsOrigins = corsOrigins
        self.publicURL = publicURL ?? ProcessInfo.processInfo.environment["MVP_DASHBOARD_PUBLIC_URL"].flatMap { URL(string: $0) }
    }

    public var home: String { runtime.home }
    public var registryPath: String { runtime.registryPath }
    public var settingsPath: String { runtime.settingsPath }
}
