import ArgumentParser
import CascadeKit
import DashboardRuntime
import DashboardService
import Foundation
import Logging

@main
struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Manage dashboard projects (kanban workspaces in folders) and run the API server.",
        version: "0.1.0",
        subcommands: [ProjectCommand.self, SettingsCommand.self, AICommand.self, MCPCommand.self, ServeCommand.self, DaemonCommand.self]
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

    var resolvedHome: String {
        home ?? DependencyValues.current.home
    }

    /// Log level for this invocation, applied through the `\.logger` dependency.
    var logLevel: Logger.Level {
        verbose ? .info : .warning
    }

    var serverURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let raw = server ?? environment["MVP_DASHBOARD_URL"]
            ?? "http://127.0.0.1:\(environment["MVP_DASHBOARD_PORT"] ?? "5175")"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:5175")!
    }

    /// An address the user pinned with `--server`. When absent the command uses this
    /// home's daemon, starting one if needed.
    var explicitServerURL: URL? {
        server.flatMap(URL.init(string:))
    }

    func validate() throws {
        if let server, URL(string: server)?.host == nil { throw ValidationError("--server must be an http(s) URL") }
    }
}
