import ArgumentParser
import CascadeKit
import DashboardDomain
import DashboardRuntime
import DashboardService
import Foundation
import Logging

@main
struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Manage dashboard projects (kanban workspaces in folders) and run the API server.",
        version: DashboardVersion.declared,
        subcommands: [ProjectCommand.self, SettingsCommand.self, AICommand.self, MCPCommand.self, ServeCommand.self, DaemonCommand.self]
    )

    @OptionGroup var global: GlobalOptions
}

struct GlobalOptions: ParsableArguments {

    @Flag(name: .long, help: "Show info-level logs (migrations, database activity) on stderr.")
    var verbose = false

    /// Where this command's data lives. There is no flag: the directory it was run
    /// from already says which home was meant, and a flag pointing somewhere else
    /// only invites two daemons disagreeing about who owns what.
    var resolvedHome: String {
        DependencyValues.current.home
    }

    /// Log level for this invocation, applied through the `\.logger` dependency.
    var logLevel: Logger.Level {
        verbose ? .info : .warning
    }
}
