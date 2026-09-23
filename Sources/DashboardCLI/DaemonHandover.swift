import DashboardClient
import DashboardRuntime
import Foundation

/// Publishing and taking over a home's `daemon.port`.
///
/// Exactly one process may open a home's databases. `serve` and `daemon` are both
/// candidates, so whichever starts second takes the home from the first rather
/// than opening the files beside it — which is the deadlock this whole design exists
/// to remove.
enum DaemonHandover {
    /// How long the previous owner has to let go before we give up.
    static let handoverTimeout: Duration = .seconds(5)

    /// Writes the port and pid so other processes can find, and displace, this owner.
    static func publish(port: Int, config: RuntimeConfig) throws {
        let line = "\(port) \(ProcessInfo.processInfo.processIdentifier)\n"
        try Data(line.utf8).write(to: URL(fileURLWithPath: config.daemonPortPath), options: .atomic)
    }

    static func withdraw(_ config: RuntimeConfig) {
        guard let handle = config.daemonHandle, handle.pid == ProcessInfo.processInfo.processIdentifier else { return }
        try? FileManager.default.removeItem(atPath: config.daemonPortPath)
    }

    /// Asks the current owner to stop and waits for it to release the home.
    /// A `SIGTERM` is what Vapor already shuts down cleanly on, so this needs no
    /// extra HTTP surface on the daemon.
    static func takeOver(_ config: RuntimeConfig) async throws {
        guard let handle = config.daemonHandle, handle.pid > 0 else { return }
        guard await DashboardClient(baseURL: URL(string: "http://127.0.0.1:\(handle.port)")!).isReachable() else {
            try? FileManager.default.removeItem(atPath: config.daemonPortPath)
            return
        }
        kill(handle.pid, SIGTERM)

        let deadline = ContinuousClock.now + handoverTimeout
        while ContinuousClock.now < deadline {
            if config.daemonHandle == nil { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CLIError.handoverTimedOut(pid: handle.pid)
    }
}
