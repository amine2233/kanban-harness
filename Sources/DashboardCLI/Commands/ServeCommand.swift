import ArgumentParser
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
            let app = try await Vapor.Application.make(environment)
            do {
                try await configure(app, config: ServerConfig(home: global.resolvedHome, staticDir: staticDir, corsOrigins: corsOrigins))
                app.http.server.configuration.hostname = hostname
                app.http.server.configuration.port = port
                try await app.execute()
            } catch {
                try? await app.asyncShutdown()
                throw error
            }
            try await app.asyncShutdown()
        }
    }
}
