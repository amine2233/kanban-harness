import ArgumentParser
import DashboardRuntime
import DashboardServer
import Foundation
import Vapor

/// The one process that opens a home's databases. Everything else — `serve`,
/// `mcp`, every one-shot command — reaches the data through it, so two writers
/// on one SQLite file cannot happen and a change made anywhere reaches every
/// subscriber.
///
/// It runs until it is told to stop. Nothing times it out: a daemon that
/// disappeared on its own would be started again by the next command, which is
/// churn without a purpose.
struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "The process that owns this home's databases.",
        subcommands: [Start.self, Stop.self, Status.self, Run.self],
        defaultSubcommand: Status.self
    )

    /// Starts one in the background and waits until it answers.
    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start the daemon for this home if it is not already running.")

        @ArgumentParser.OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                let client = try await DaemonProcess.connect(explicit: nil, home: global.resolvedHome)
                try Output.json(Report(home: global.resolvedHome, running: true, url: client.baseURL.absoluteString))
            }
        }
    }

    /// Stops it, so an always-running daemon is still under the user's control.
    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop the daemon owning this home.")

        @ArgumentParser.OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                let config = RuntimeConfig(home: global.resolvedHome)
                try await DaemonHandover.takeOver(config)
                try Output.json(Report(home: config.home, running: false, url: nil))
            }
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Report whether a daemon owns this home.")

        @ArgumentParser.OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                let config = RuntimeConfig(home: global.resolvedHome)
                let url = config.daemonURL
                try Output.json(Report(home: config.home, running: url != nil, url: url?.absoluteString))
            }
        }
    }

    /// The daemon itself, in the foreground. `Start` spawns this.
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the daemon in the foreground until it is stopped.",
            discussion: """
                Binds 127.0.0.1 on a port of its own and writes it, with its pid, to
                `daemon.port` in the home — so two homes never share a daemon and
                whoever takes the home over knows whom to ask to let go.
                """
        )

        @ArgumentParser.OptionGroup var global: GlobalOptions

        func run() async throws {
            try await failing {
                let config = ServerConfig(home: global.resolvedHome)
                var environment = Environment.production
                environment.arguments = [CommandLine.arguments.first ?? "dashboard", "serve"]
                let app = try await Vapor.Application.make(environment)
                do {
                    try await DaemonHandover.takeOver(config.runtime)
                    try await configure(app, config: config)
                    app.http.server.configuration.hostname = "127.0.0.1"
                    app.http.server.configuration.port = 0
                    try await app.startup()
                    guard let port = app.http.server.shared.localAddress?.port else { throw CLIError.daemonDidNotBind }
                    try DaemonHandover.publish(port: port, config: config.runtime)
                    try await app.running?.onStop.get()
                } catch {
                    DaemonHandover.withdraw(config.runtime)
                    try? await app.asyncShutdown()
                    throw error
                }
                DaemonHandover.withdraw(config.runtime)
                try await app.asyncShutdown()
            }
        }
    }

    struct Report: Encodable {
        let home: String
        let running: Bool
        let url: String?
    }
}
