import CascadeKit
import DashboardService
import Foundation

/// Where the process keeps its own data. Defaults to the `\.home` dependency.
public struct RuntimeConfig: Sendable, Equatable {
    public static let registryFileName = "projects.sqlite"
    public static let settingsFileName = "settings.json"

    public var home: String

    public init(home: String? = nil) {
        self.home = home ?? DependencyValues.current.home
    }

    public var registryPath: String {
        (home as NSString).appendingPathComponent(Self.registryFileName)
    }

    public var settingsPath: String {
        (home as NSString).appendingPathComponent(Self.settingsFileName)
    }
}
