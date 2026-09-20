import ArgumentParser
import CascadeKit
import DashboardService
import Logging

@main
struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Manage dashboard projects (kanban workspaces in folders) and run the API server.",
        version: "0.1.0",
        subcommands: [ProjectCommand.self, SettingsCommand.self, ServeCommand.self]
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

    var resolvedHome: String {
        home ?? DependencyValues.current.home
    }

    /// Log level for this invocation, applied through the `\.logger` dependency.
    var logLevel: Logger.Level {
        verbose ? .info : .warning
    }
}
