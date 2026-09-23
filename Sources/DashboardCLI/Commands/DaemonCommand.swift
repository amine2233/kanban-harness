import ArgumentParser
import DashboardRuntime
import DashboardServer
import Foundation
import Vapor

/// Tracks when the daemon was last useful, so it can stop on its own.
private actor LastActivity {
    private var at = ContinuousClock.now
    func touch() { at = ContinuousClock.now }
    func idleFor() -> Duration { ContinuousClock.now - at }
}

/// Bumps the clock on every request, including the ones that never reach a route.
private struct ActivityMiddleware: AsyncMiddleware {
    let activity: LastActivity

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        await activity.touch()
        return try await next.respond(to: request)
    }
}

/// The one process that opens the databases. Everything else — `serve`, `mcp`,
/// every one-shot command — reaches the data through it, so two writers on one
/// SQLite file cannot happen and a change made anywhere reaches every subscriber.
struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Own the databases for a home and serve them on a loopback port.",
        discussion: """
            Started on demand by any other command, so it is rarely run by hand.
            It binds 127.0.0.1 on a port of its own and writes it to `daemon.port`
            in the home, so two homes never share a daemon. It stops after
            $MVP_DASHBOARD_DAEMON_IDLE seconds without a request (default 300).
            `serve` is what a browser talks to; this is not.
            """
    )

    @ArgumentParser.OptionGroup var global: GlobalOptions

    func run() async throws {
        try await failing {
            let config = ServerConfig(home: global.resolvedHome)
            let activity = LastActivity()
            var environment = Environment.production
            environment.arguments = [CommandLine.arguments.first ?? "dashboard", "serve"]
            let app = try await Vapor.Application.make(environment)
            do {
                try await configure(app, config: config)
                app.middleware.use(ActivityMiddleware(activity: activity), at: .beginning)
                app.http.server.configuration.hostname = "127.0.0.1"
                app.http.server.configuration.port = config.runtime.daemonURL?.port ?? 0
                try await app.startup()
                try publishPort(app, config: config.runtime)
                try await stopWhenIdle(app, activity: activity, after: config.runtime.daemonIdleTimeout)
            } catch {
                try? removePortFile(config.runtime)
                try? await app.asyncShutdown()
                throw error
            }
            try? removePortFile(config.runtime)
            try await app.asyncShutdown()
        }
    }

    /// The port is only knowable after the bind, and it is how every other
    /// process finds this home's daemon — so it is written, not guessed.
    private func publishPort(_ app: Vapor.Application, config: RuntimeConfig) throws {
        guard let port = app.http.server.shared.localAddress?.port else {
            throw CLIError.daemonDidNotBind
        }
        try Data("\(port)\n".utf8).write(to: URL(fileURLWithPath: config.daemonPortPath), options: .atomic)
    }

    private func removePortFile(_ config: RuntimeConfig) throws {
        try FileManager.default.removeItem(atPath: config.daemonPortPath)
    }

    private func stopWhenIdle(_ app: Vapor.Application, activity: LastActivity, after timeout: Duration) async throws {
        while true {
            let idle = await activity.idleFor()
            if idle >= timeout { return }
            try await Task.sleep(for: min(timeout - idle, .seconds(5)))
        }
    }
}
