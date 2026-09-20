import CascadeKit
import DashboardRuntime

/// One cascade-kit container per command invocation, wired exactly like the
/// server's, torn down when the command ends (also on failure).
struct Runtime {
    let container = CascadeKit.Application()

    init(home: String) async throws {
        try await DashboardRuntime.register(on: container, config: RuntimeConfig(home: home))
    }

    func run<T>(_ body: (any Container) async throws -> T) async throws -> T {
        do {
            let result = try await body(container)
            await DashboardRuntime.shutdown(container)
            return result
        } catch {
            await DashboardRuntime.shutdown(container)
            throw error
        }
    }

    /// Opens the runtime for `global.resolvedHome` with the invocation's log
    /// level bound as the `\.logger` dependency, runs `body`, shuts down.
    static func run<T>(_ global: GlobalOptions, _ body: (any Container) async throws -> T) async throws -> T {
        try await withDependencies {
            $0.logger.logLevel = global.logLevel
        } operation: {
            try await Runtime(home: global.resolvedHome).run(body)
        }
    }
}
