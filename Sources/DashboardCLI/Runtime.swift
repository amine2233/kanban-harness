import CascadeKit
import DashboardClient
import DashboardRuntime
import DashboardService
import Foundation

/// One cascade-kit container per command invocation, wired with HTTP
/// implementations of the command protocols pointed at the daemon.
///
/// There is no second wiring: the daemon is the only process that opens a
/// database, so a command never holds a store and two writers on one SQLite
/// file cannot happen.
struct Runtime {
    let container = CascadeKit.Application()

    static func open(_ global: GlobalOptions) async throws -> Runtime {
        let client = try await DaemonProcess.connect(home: global.resolvedHome)
        let runtime = Runtime()
        runtime.container.register(ProjectCommandsKey.self) { _ in RemoteProjectCommands(client: client)
        }
        runtime.container.register(SettingsCommandsKey.self) { _ in RemoteSettingsCommands(client: client)
        }
        runtime.container.register(AIConfigCommandsKey.self) { _ in RemoteAIConfigCommands(client: client)
        }
        runtime.container.register(BoardCommandsKey.self) { _ in
            RemoteBoardCommands(client: client)
        }
        runtime.container.register(AssistantCommandsKey.self) { _ in RemoteAssistantCommands(client: client)
        }
        runtime.container.register(SignInCommandsKey.self) { _ in RemoteSignInCommands(client: client)
        }
        DependencyValues.current.logger.debug(
            "dashboard cli daemon: \(client.baseURL.absoluteString)"
        )
        return runtime
    }

    func run<T>(_ body: (any Container) async throws -> T) async throws -> T {
        try await body(container)
    }

    /// Opens the runtime for `global` with its log level bound as the `\.logger` dependency, and runs `body`.
    static func run<T>(_ global: GlobalOptions, _ body: (any Container) async throws -> T) async throws -> T {
        try await withDependencies {
            $0.logger.logLevel = global.logLevel
        } operation: {
            try await open(global).run(body)
        }
    }
}
