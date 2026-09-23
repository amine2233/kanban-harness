import DashboardClient
import DashboardRuntime
import Foundation

/// The module's error type.
enum CLIError: LocalizedError {
    case daemonUnavailable(home: String)
    case daemonDidNotBind
    case handoverTimedOut(pid: Int32)

    var errorDescription: String? {
        switch self {
        case let .daemonUnavailable(home):
            "no dashboard daemon for \(home) and starting one timed out; run `dashboard daemon --home \(home)` to see why"
        case .daemonDidNotBind:
            "the daemon could not bind a loopback port"
        case let .handoverTimedOut(pid):
            "process \(pid) still owns this home after being asked to stop; kill it and retry"
        }
    }
}

/// Finds the daemon, starting one when nothing answers.
///
/// The daemon owns every database, so a command that cannot reach it has no
/// fallback by design — falling back to the files is what used to corrupt them.
enum DaemonProcess {
    /// How long a freshly spawned daemon has to answer before the command gives up.
    static let startTimeout: Duration = .seconds(10)
    /// A lock older than this belonged to a spawner that died before releasing it.
    static let staleLockAfter: TimeInterval = 30

    static func connect(home: String) async throws -> DashboardClient {
        if let client = await currentBuildClient(home: home) { return client }

        // Either nothing owns the home, or an older build does. Asking it to let
        // go covers both: a daemon left by the previous binary would otherwise
        // keep answering on the same port and never be replaced.
        try await DaemonHandover.takeOver(RuntimeConfig(home: home))
        try spawnUnlessAnotherIsStarting(home: home)

        let deadline = ContinuousClock.now + startTimeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            if let client = await currentBuildClient(home: home) { return client }
        }
        throw CLIError.daemonUnavailable(home: home)
    }

    /// Re-read the port file every attempt: it does not exist until the daemon binds.
    /// A daemon from another build does not count as an owner we can use.
    private static func currentBuildClient(home: String) async -> DashboardClient? {
        guard let url = RuntimeConfig(home: home).daemonURL else { return nil }
        let client = DashboardClient(baseURL: url)
        return await client.isSameBuild() ? client : nil
    }

    /// Two commands racing must produce one daemon. `createDirectory` with
    /// `withIntermediateDirectories: false` is the atomic test-and-set: it throws
    /// when the directory already exists, and needs no POSIX import to be portable.
    private static func spawnUnlessAnotherIsStarting(home: String) throws {
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        let lock = (home as NSString).appendingPathComponent("daemon.lock")

        if let modified = try? FileManager.default.attributesOfItem(atPath: lock)[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > staleLockAfter {
            try? FileManager.default.removeItem(atPath: lock)
        }

        do {
            try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: false)
        } catch {
            return  // another command is already starting it; the caller polls
        }
        defer { try? FileManager.default.removeItem(atPath: lock) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["daemon", "run"]
        // The home is not a flag, so it travels to the child the only way it can.
        process.environment = ProcessInfo.processInfo.environment.merging(["MVP_DASHBOARD_HOME": home]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// ponytail: spawned into the caller's process group, so Ctrl-C on a command
    /// that just started the daemon stops it too. A `setsid` launcher fixes it if
    /// that ever bites; nothing in the normal path depends on it.
    private static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? "dashboard"
    }
}
