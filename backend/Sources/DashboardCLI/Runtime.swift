import CascadeKit
import DashboardClient
import DashboardRuntime
import DashboardService
import Foundation

/// How a command reaches the data: through a running server (the source of
/// truth) or, when none answers, by owning the files itself.
enum Mode: String, Sendable {
    case remote
    case local
}

/// One cascade-kit container per command invocation, wired either like the
/// server's (local) or with HTTP implementations of the same command
/// protocols (remote); torn down when the command ends, also on failure.
struct Runtime {
    let container = CascadeKit.Application()
    let mode: Mode

    private init(mode: Mode) {
        self.mode = mode
    }

    static func open(_ global: GlobalOptions) async throws -> Runtime {
        let client = DashboardClient(baseURL: global.serverURL)
        let mode: Mode
        switch global.forcedMode {
        case .some(let forced): mode = forced
        case .none: mode = await client.isReachable() ? .remote : .local
        }
        let runtime = Runtime(mode: mode)
        switch mode {
        case .remote:
            runtime.container.register(ProjectCommandsKey.self) { _ in RemoteProjectCommands(client: client) }
            runtime.container.register(SettingsCommandsKey.self) { _ in RemoteSettingsCommands(client: client) }
            runtime.container.register(AIConfigCommandsKey.self) { _ in RemoteAIConfigCommands(client: client) }
        case .local:
            try await DashboardRuntime.register(on: runtime.container, config: RuntimeConfig(home: global.resolvedHome))
        }
        DependencyValues.current.logger.debug("dashboard cli mode: \(mode.rawValue) (\(global.serverURL.absoluteString))")
        return runtime
    }

    func run<T>(_ body: (any Container) async throws -> T) async throws -> T {
        do {
            let result = try await body(container)
            await shutdown()
            return result
        } catch {
            await shutdown()
            throw error
        }
    }

    private func shutdown() async {
        if mode == .local { await DashboardRuntime.shutdown(container) }
    }

    /// Opens the runtime for `global` with its log level bound as the `\.logger` dependency, runs `body`, shuts down.
    static func run<T>(_ global: GlobalOptions, _ body: (any Container) async throws -> T) async throws -> T {
        try await withDependencies {
            $0.logger.logLevel = global.logLevel
        } operation: {
            try await open(global).run(body)
        }
    }
}
