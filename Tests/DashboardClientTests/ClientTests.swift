import DashboardAI
import DashboardAPI
import DashboardDomain
import DashboardServer
import DashboardService
import Foundation
import Testing
import Vapor
@testable import DashboardClient

/// The client is exercised against a real running server so both ends of the wire are covered.
@Suite(.serialized)
struct ClientTests {
    /// A daemon older than the `version` field answers without one; that has to
    /// decode as "unknown build", not as a broken response, or the upgrade path
    /// would look like an unreachable daemon.
    @Test
    func healthDecodesADaemonThatReportsNoBuild() throws {
        let current = try JSONDecoder().decode(
            HealthResponse.self,
            from: Data(#"{"status":"ok","version":"9.9"}"#.utf8)
        )
        #expect(current.version == "9.9")
        let old = try JSONDecoder().decode(HealthResponse.self, from: Data(#"{"status":"ok"}"#.utf8))
        #expect(old.status == "ok")
        #expect(old.version == nil)
    }

    func withServer(
        claude: String? = nil,
        _ body: (DashboardClient, String) async throws -> Void
    ) async throws {
        let home = NSTemporaryDirectory() + "mvp-dashboard-client-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        var environment = Environment.testing
        environment.arguments = ["vapor"]
        let app = try await Application.make(environment)
        do {
            try await configure(
                app,
                config: ServerConfig(home: home, claudeExecutable: claude ?? "/nonexistent/claude")
            )
            app.http.server.configuration.hostname = "127.0.0.1"
            app.http.server.configuration.port = 0
            try await app.startup()
            let port = try #require(app.http.server.shared.localAddress?.port)
            try await body(DashboardClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!), home)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test
    func reachabilityReflectsARunningServer() async throws {
        try await withServer { client, _ in
            #expect(await client.isReachable())
        }
        let dead = try DashboardClient(baseURL: #require(URL(string: "http://127.0.0.1:1")))
        #expect(await !dead.isReachable())
    }

    @Test
    func projectCommandsRoundTripThroughTheServer() async throws {
        try await withServer { client, home in
            let projects = RemoteProjectCommands(client: client)
            #expect(try await projects.list().isEmpty)

            let created = try await projects.add(name: "Remote", path: home + "/remote", storage: nil)
            #expect(created.storage == .json, "nil storage follows the server default")
            #expect(try await projects.get(.name("remote")) == created)
            #expect(try await projects.get(.id(created.id)) == created)

            let boards = try await projects.boards(.name("Remote"))
            #expect(boards.map(\.name) == ["Remote"])

            let switched = try await projects.changeStorage(.id(created.id), to: .sqlite)
            #expect(switched.storage == .sqlite)
            #expect(FileManager.default.fileExists(atPath: home + "/remote/kanban.sqlite"))

            let removed = try await projects.remove(.name("Remote"))
            #expect(removed.id == created.id)
            #expect(try await projects.list().isEmpty)
        }
    }

    @Test
    func serverErrorsBecomeTypedServiceErrors() async throws {
        try await withServer { client, home in
            let projects = RemoteProjectCommands(client: client)
            await #expect(throws: ServiceError.self) { try await projects.get(.name("ghost")) }
            do { _ = try await projects.get(.name("ghost")) } catch let error as ServiceError {
                #expect(error.isNotFound)
            }

            _ = try await projects.add(name: "Dup", path: home + "/a", storage: nil)
            do {
                _ = try await projects.add(name: "dup", path: home + "/b", storage: nil)
                Issue.record("expected conflict")
            } catch let error as ServiceError {
                #expect(error.isConflict)
                #expect(error.localizedDescription.contains("already exists"))
            }
            do {
                _ = try await projects.add(name: "x", path: "relative", storage: nil)
                Issue.record("expected validation")
            } catch let error as ServiceError {
                #expect(error.isValidation)
            }
        }
    }

    @Test
    func settingsCommandsRoundTrip() async throws {
        try await withServer { client, _ in
            let settings = RemoteSettingsCommands(client: client)
            #expect(try await settings.current() == .default)
            let updated = try await settings.update(
                defaultStorage: .sqlite,
                corsOrigins: ["http://localhost:5173/"]
            )
            #expect(updated == Settings(defaultStorage: .sqlite, corsOrigins: ["http://localhost:5173"]))
            let projects = RemoteProjectCommands(client: client)
            let created = try await projects.add(
                name: "Follows default",
                path: NSTemporaryDirectory() + "fd-" + UUID().uuidString,
                storage: nil
            )
            #expect(created.storage == .sqlite)
        }
    }

    @Test
    func aiConfigCommandsRoundTripWithRedactedKeys() async throws {
        try await withServer { client, _ in
            let ai = RemoteAIConfigCommands(client: client)
            #expect(try await ai.current() == .empty)
            let claude = try AIProviderConfig(
                id: "claude",
                kind: .anthropic,
                name: "Claude",
                model: "claude-sonnet-5",
                apiKey: "sk-1"
            )
            let config = try await ai.upsert(claude)
            #expect(config.defaultProviderId == "claude")
            #expect(
                config.provider("claude")?.apiKey == RemoteAIConfigCommands.redactedKey,
                "server never returns the key"
            )
            _ = try await ai.upsert(AIProviderConfig(
                id: "local",
                kind: .ollama,
                name: "Ollama",
                model: "llama3.2"
            ))
            #expect(try await ai.setDefault("local").defaultProviderId == "local")
            #expect(try await ai.remove("claude").providers.map(\.id) == ["local"])
            do {
                _ = try await ai.remove("ghost")
                Issue.record("expected not found")
            } catch let error as ServiceError {
                #expect(error.isNotFound)
            }
        }
    }

    @Test
    func unreachableServerIsReportedAsSuch() async throws {
        let projects = try RemoteProjectCommands(client: DashboardClient(
            baseURL: #require(URL(string: "http://127.0.0.1:1")),
            timeout: 1
        ))
        do {
            _ = try await projects.list()
            Issue.record("expected unreachable")
        } catch let error as ServiceError {
            guard case .unreachable = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
    }

    @Test
    func assistantStreamsFramesBackIntoEvents() async throws {
        let dir = NSTemporaryDirectory() + "claude-stub-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stub = dir + "/claude"
        try """
        #!/bin/sh
        echo '{"type":"stream_event","event":{"delta":{"partial_json":"{\\"title\\":\\"Str"}}}'
        echo '{"type":"result","is_error":false,"structured_output":{"title":"Streamed","priority":"low","acceptance_criteria":["a"]},"usage":{"input_tokens":1,"output_tokens":2}}'
        """.write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
        try await withServer(claude: stub) { client, home in
            let projects = RemoteProjectCommands(client: client)
            _ = try await projects.add(name: "Demo", path: home + "/demo", storage: nil)
            _ = try await RemoteAIConfigCommands(client: client).upsert(AIProviderConfig(
                id: "cc",
                kind: .claudeCode,
                name: "CC",
                model: "sonnet"
            ))
            let board = try #require(try await projects.boards(.name("Demo")).first)
            let assistant = RemoteAssistantCommands(client: client)

            var stages: [AssistantStage.Step] = []
            var partials: [PartialTicketDraft] = []
            var result: DraftedTicket?
            for try await event in assistant.streamTicket(
                project: .name("Demo"),
                boardId: board.id,
                idea: "x",
                providerId: nil
            ) {
                switch event {
                case let .stage(stage): stages.append(stage.step)
                case let .partial(p): partials.append(p)
                case .usage, .text: break
                case let .result(r): result = r
                }
            }
            #expect(stages.first == .resolve && stages.last == .done)
            #expect(partials.map { $0.title } == ["Str"])
            #expect(result?.draft.title == "Streamed")
            #expect(result?.usage == CompletionUsage(inputTokens: 1, outputTokens: 2))
            #expect(try await assistant.draftTicket(
                project: .name("Demo"),
                boardId: board.id,
                idea: "x",
                providerId: nil
            ).draft.title == "Streamed")

            do {
                _ = try await assistant.draftTicket(
                    project: .name("Demo"),
                    boardId: board.id,
                    idea: "x",
                    providerId: "ghost"
                )
                Issue.record("expected not found")
            } catch let error as ServiceError {
                #expect(error.isNotFound)
            }
        }
    }
}
