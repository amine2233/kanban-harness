import CascadeKit
import Foundation
import Logging

/// Cross-cutting values resolved through cascade-kit so tests can pin time,
/// ids, the data directory and logging with `withTestDependencies`.
public enum NowKey: DependencyKey {
    public static let liveValue: @Sendable () -> Date = { .timestamp() }
}

public enum UUIDKey: DependencyKey {
    public static let liveValue: @Sendable () -> UUID = { UUID() }
}

/// Directory holding the project registry and settings.json.
/// `$MVP_DASHBOARD_HOME`, else `$XDG_CONFIG_HOME/mvp-dashboard`, else `~/.config/mvp-dashboard`.
public enum HomeKey: DependencyKey {
    public static let liveValue: String = defaultHome()

    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let home = environment["MVP_DASHBOARD_HOME"] { return home }
        let config = environment["XDG_CONFIG_HOME"]
            ?? (environment["HOME"].map { $0 + "/.config" } ?? NSHomeDirectory() + "/.config")
        return config + "/mvp-dashboard"
    }
}

public enum LoggerKey: DependencyKey {
    public static let liveValue = Logger(label: "dashboard")
}

extension DependencyValues {
    public var now: @Sendable () -> Date {
        get { self[NowKey.self] }
        set { self[NowKey.self] = newValue }
    }

    public var uuid: @Sendable () -> UUID {
        get { self[UUIDKey.self] }
        set { self[UUIDKey.self] = newValue }
    }

    public var home: String {
        get { self[HomeKey.self] }
        set { self[HomeKey.self] = newValue }
    }

    public var logger: Logger {
        get { self[LoggerKey.self] }
        set { self[LoggerKey.self] = newValue }
    }
}
