import Foundation

public struct ServerConfig: Sendable {
    public static let registryFileName = "projects.sqlite"
    public static let settingsFileName = "settings.json"

    /// Directory holding the project registry database.
    public var home: String
    /// Built frontend to serve alongside the API (SPA fallback to index.html).
    public var staticDir: String?
    /// Extra browser origins allowed to call the API, on top of `settings.json`.
    public var corsOrigins: [String]

    public init(home: String, staticDir: String? = nil, corsOrigins: [String] = []) {
        self.home = home
        self.staticDir = staticDir
        self.corsOrigins = corsOrigins
    }

    public var registryPath: String {
        (home as NSString).appendingPathComponent(Self.registryFileName)
    }

    public var settingsPath: String {
        (home as NSString).appendingPathComponent(Self.settingsFileName)
    }

    /// `$MVP_DASHBOARD_HOME`, else `$XDG_CONFIG_HOME/mvp-dashboard`, else `~/.config/mvp-dashboard`.
    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let home = environment["MVP_DASHBOARD_HOME"] { return home }
        let config = environment["XDG_CONFIG_HOME"]
            ?? (environment["HOME"].map { $0 + "/.config" } ?? NSHomeDirectory() + "/.config")
        return config + "/mvp-dashboard"
    }
}
