import ArgumentParser
import DashboardRuntime
import DashboardServer
import Foundation
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

    @ArgumentParser.Option(
        name: .customLong("public-url"),
        help: "Origin a browser reaches this dashboard at, e.g. http://127.0.0.1:5173. The OAuth redirect URI and the post-sign-in landing are built from it, so it must be an origin that serves the app. Without it only a loopback Host is accepted. Also MVP_DASHBOARD_PUBLIC_URL."
    )
    var publicURL: String?

    func run() async throws {
        try await failing {
            var environment = Environment.production
            environment.arguments = [CommandLine.arguments.first ?? "dashboard", "serve"]
            let origin = try publicURL.map { text in
                guard let url = URL(string: text), url.scheme != nil, url.host() != nil else {
                    throw ValidationError("--public-url must be an absolute origin, e.g. http://127.0.0.1:5173")
                }
                return url
            }
            let config = ServerConfig(home: global.resolvedHome, staticDir: staticDir, corsOrigins: corsOrigins, publicURL: origin)
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
