import ArgumentParser
import DashboardRuntime
import DashboardServer
import Vapor

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "serve", abstract: "Run the HTTP API server.")

    @ArgumentParser.OptionGroup var global: GlobalOptions

    @ArgumentParser.Option(help: "Address to bind.")
    var hostname: String = "127.0.0.1"

    @ArgumentParser.Option(help: "Port to bind.")
    var port: Int = 5175

    @ArgumentParser.Option(name: .customLong("static-dir"), help: "Serve a built frontend directory alongside the API.")
    var staticDir: String?

    @ArgumentParser.Option(
        name: .customLong("cors-origin"),
        parsing: .upToNextOption,
        help: "Browser origin(s) allowed to call the API from another host, e.g. http://localhost:5173."
    )
    var corsOrigins: [String] = []

    func run() async throws {
        try await failing {
            var environment = Environment.production
            environment.arguments = [CommandLine.arguments.first ?? "dashboard", "serve"]
            let config = ServerConfig(home: global.resolvedHome, staticDir: staticDir, corsOrigins: corsOrigins)
            let app = try await Vapor.Application.make(environment)
            do {
                // Serving a home means owning it: a daemon started earlier by some
                // command must let go, or both would open the same databases.
                try await DaemonHandover.takeOver(config.runtime)
                try await configure(app, config: config)
                app.http.server.configuration.hostname = hostname
                app.http.server.configuration.port = port
                try await app.startup()
                guard let bound = app.http.server.shared.localAddress?.port else { throw CLIError.daemonDidNotBind }
                try DaemonHandover.publish(port: bound, config: config.runtime)
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
