import ArgumentParser
import DashboardAI
import DashboardClient
import DashboardDomain
import DashboardRuntime
import DashboardServer
import Foundation
import Vapor

extension AICommand.Providers {
    /// Browser sign-in. With a dashboard server running, the server owns the
    /// callback; otherwise a temporary loopback server is started for the
    /// duration of the sign-in.
    struct Login: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sign a provider in through the browser (OpenRouter, Hugging Face).")
        @ArgumentParser.OptionGroup var global: GlobalOptions

        @ArgumentParser.Argument(help: "Provider id.")
        var id: String

        @ArgumentParser.Option(help: "Seconds to wait for the browser round trip.")
        var timeout: Int = 300

        @ArgumentParser.Flag(name: .customLong("no-open"), help: "Print the URL instead of opening the browser.")
        var noOpen = false

        func run() async throws {
            try await failing {
                let client = DashboardClient(baseURL: global.serverURL)
                if global.forcedMode != .local, await client.isReachable() {
                    try await viaServer(client)
                } else {
                    try await viaTemporaryServer()
                }
            }
        }

        private func viaServer(_ client: DashboardClient) async throws {
            let signIn = RemoteSignInCommands(client: client)
            let url = try await signIn.begin(providerId: id, callback: global.serverURL)
            try open(url)
            let config = RemoteAIConfigCommands(client: client)
            try await waitUntil { try await config.current().provider(id)?.hasAPIKey == true }
            try Output.json(AICommand.Providers.View(try await config.current()))
        }

        private func viaTemporaryServer() async throws {
            var environment = Environment.production
            environment.arguments = [CommandLine.arguments.first ?? "dashboard", "serve"]
            let app = try await Vapor.Application.make(environment)
            do {
                try await configure(app, config: ServerConfig(home: global.resolvedHome))
                app.http.server.configuration.hostname = "127.0.0.1"
                app.http.server.configuration.port = 0
                try await app.startup()
                guard let port = app.http.server.shared.localAddress?.port, let callback = URL(string: "http://127.0.0.1:\(port)/api/auth/callback") else {
                    throw ValidationError("could not bind a loopback port for the callback")
                }
                let signIn = app.services.make(SignInCommandsKey.self)
                try open(try await signIn.begin(providerId: id, callback: callback))
                let credentials = app.services.make(CredentialStoreKey.self)
                try await waitUntil { try await credentials.get(id) != nil }
                try Output.json(AICommand.Providers.View(try await app.services.make(AIConfigCommandsKey.self).current()))
            } catch {
                try? await app.asyncShutdown()
                throw error
            }
            try await app.asyncShutdown()
        }

        private func open(_ url: URL) throws {
            FileHandle.standardError.write(Data("Open this URL to sign in:\n\(url.absoluteString)\n".utf8))
            guard !noOpen, let opener = ["/usr/bin/open", "/usr/bin/xdg-open"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: opener)
            process.arguments = [url.absoluteString]
            try? process.run()
        }

        private func waitUntil(_ done: () async throws -> Bool) async throws {
            let deadline = Date().addingTimeInterval(TimeInterval(timeout))
            while Date() < deadline {
                if try await done() { return }
                try await Task.sleep(for: .seconds(1))
            }
            throw ValidationError("timed out after \(timeout)s waiting for the sign-in to complete")
        }
    }

    struct Logout: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Forget a provider's stored credential.")
        @ArgumentParser.OptionGroup var global: GlobalOptions

        @ArgumentParser.Argument(help: "Provider id.")
        var id: String

        func run() async throws {
            try await failing {
                try Output.json(AICommand.Providers.View(try await Runtime.run(global) { container in
                    try await container.make(SignInCommandsKey.self).signOut(providerId: id)
                    return try await container.make(AIConfigCommandsKey.self).current()
                }))
            }
        }
    }
}
