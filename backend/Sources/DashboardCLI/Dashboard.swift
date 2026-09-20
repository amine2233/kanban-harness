import ArgumentParser
import CascadeKit
import DashboardService
import Foundation
import Logging

@main
struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Manage dashboard projects (kanban workspaces in folders) and run the API server.",
        version: "0.1.0",
        subcommands: [ProjectCommand.self, SettingsCommand.self, AICommand.self, ServeCommand.self]
    )

    @OptionGroup var global: GlobalOptions
}

struct GlobalOptions: ParsableArguments {
    @Option(
        name: .long,
        help: "Directory holding the project registry (default: $MVP_DASHBOARD_HOME or $XDG_CONFIG_HOME/mvp-dashboard)."
    )
    var home: String?

    @Flag(name: .long, help: "Show info-level logs (migrations, database activity) on stderr.")
    var verbose = false

    @Option(
        name: .customLong("server"),
        help: "Dashboard server to talk to (default: $MVP_DASHBOARD_URL, else http://127.0.0.1:$MVP_DASHBOARD_PORT|5175)."
    )
    var server: String?

    @Flag(name: .customLong("local"), help: "Work on the files directly even if a server is running.")
    var local = false

    @Flag(name: .customLong("remote"), help: "Require a running server; fail instead of falling back to the files.")
    var remote = false

    var resolvedHome: String {
        home ?? DependencyValues.current.home
    }

    /// Log level for this invocation, applied through the `\.logger` dependency.
    var logLevel: Logger.Level {
        verbose ? .info : .warning
    }

    var forcedMode: Mode? {
        if local { return .local }
        if remote { return .remote }
        return nil
    }

    var serverURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let raw = server ?? environment["MVP_DASHBOARD_URL"]
            ?? "http://127.0.0.1:\(environment["MVP_DASHBOARD_PORT"] ?? "5175")"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:5175")!
    }

    func validate() throws {
        if local, remote { throw ValidationError("--local and --remote are mutually exclusive") }
        if let server, URL(string: server)?.host == nil { throw ValidationError("--server must be an http(s) URL") }
    }
}
