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

/// Directory holding the registry, `config.yml`, the credentials and the daemon handle.
///
/// A project can keep its own by creating `.kanban-harness/` beside the code, which is then
/// used for commands run from that folder; everything else shares the one under the user's
/// config directory. There is no flag: the working directory already says which you meant.
public enum HomeKey: DependencyKey {
    public static let liveValue: String = defaultHome()

    /// A per-folder home, used when it exists in the directory the command was run from.
    public static let localDirectoryName = ".kanban-harness"

    /// `$MVP_DASHBOARD_HOME`, else `./.kanban-harness` when it exists, else
    /// `$XDG_CONFIG_HOME/kanban-harness`, else `~/.config/kanban-harness`.
    public static func defaultHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) -> String {
        if let home = environment["MVP_DASHBOARD_HOME"] { return home }

        let local = (currentDirectory as NSString).appendingPathComponent(localDirectoryName)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: local, isDirectory: &isDirectory), isDirectory.boolValue {
            return local
        }

        let config = environment["XDG_CONFIG_HOME"]
            ?? (environment["HOME"].map { $0 + "/.config" } ?? NSHomeDirectory() + "/.config")
        return config + "/kanban-harness"
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
