import DashboardAI
import DashboardDomain
import Foundation
import Testing
import Vapor
@testable import DashboardAIProviders

/// HTTP vendors go through AnyLanguageModel, checked here against a stub
/// Vapor server that records the request and answers in the vendor's shape.
/// Claude Code is checked against a stub `claude` executable.
@Suite(.serialized) struct ProvidersTests {
    struct Recorded: @unchecked Sendable {
        let path: String
        let headers: [String: String]
        let body: [String: Any]
    }

    actor Recorder {
        var requests: [Recorded] = []
        func add(_ r: Recorded) { requests.append(r) }
        func first() -> Recorded? { requests.first }
    }

    func withStub(_ answer: String, contentType: HTTPMediaType = .json, _ body: (URL, Recorder) async throws -> Void) async throws {
        var environment = Environment.testing
        environment.arguments = ["vapor"]
        let app = try await Application.make(environment)
        let recorder = Recorder()
        app.on(.POST, "**", body: .collect) { req -> Response in
            let json = (try? JSONSerialization.jsonObject(with: Data(buffer: req.body.data ?? ByteBuffer()))) as? [String: Any] ?? [:]
            var headers: [String: String] = [:]
            for (n, v) in req.headers { headers[n.lowercased()] = v }
            await recorder.add(Recorded(path: req.url.path, headers: headers, body: json))
            let response = Response(status: .ok)
            response.headers.contentType = contentType
            response.body = .init(string: answer)
            return response
        }
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 0
        try await app.startup()
        do {
            let port = try #require(app.http.server.shared.localAddress?.port)
            try await body(URL(string: "http://127.0.0.1:\(port)")!, recorder)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    let request = CompletionRequest(system: "sys", prompt: "draft", schema: TicketDraft.jsonSchema, maxTokens: 300)

    func collect(_ provider: any AIProvider) async throws -> [CompletionEvent] {
        var events: [CompletionEvent] = []
        for try await event in provider.stream(request) { events.append(event) }
        return events
    }

    func snapshots(_ events: [CompletionEvent]) -> [PartialTicketDraft] {
        events.compactMap { if case let .snapshot(data) = $0 { PartialTicketDraft.parse(data) } else { nil } }
    }

    @Test func ollamaStreamsPartialDraftsThroughAnyLanguageModel() async throws {
        let lines = [
            #"{"model":"llama3.2","created_at":"2026-01-01T00:00:00Z","message":{"role":"assistant","content":"{\"title\":\"Lo"},"done":false}"#,
            #"{"model":"llama3.2","created_at":"2026-01-01T00:00:00Z","message":{"role":"assistant","content":"cal\",\"priority\":\"medium\"}"},"done":true,"prompt_eval_count":7,"eval_count":8}"#,
        ]
        try await withStub(lines.joined(separator: "\n") + "\n", contentType: .init(type: "application", subType: "x-ndjson")) { base, recorder in
            let config = try AIProviderConfig(id: "l", kind: .ollama, name: "L", model: "llama3.2", baseURL: base.absoluteString)
            let events = try await collect(try AIProviderRegistry.standard.make(config))
            let partials = snapshots(events)
            #expect(partials.first?.title == "Lo")
            #expect(partials.last?.priority == .medium)
            guard case let .done(json, model) = try #require(events.last) else { Issue.record("no done event"); return }
            #expect(model == "llama3.2")
            #expect(try TicketDraft.parse(json).title == "Local")
            #expect(events.contains(.usage(CompletionUsage(inputTokens: 7, outputTokens: 8))))
            let sent = try #require(await recorder.first())
            #expect(sent.path == "/api/chat")
            #expect(sent.body["stream"] as? Bool == true)
            #expect(sent.body["format"] != nil)
        }
    }

    @Test func keyedVendorsWithoutAKeyAreNotConfigured() async throws {
        for kind in [AIProviderKind.anthropic, .gemini] {
            let config = try AIProviderConfig(id: "a", kind: kind, name: "A", model: "m")
            await #expect(throws: AIProviderError.notConfigured("A has no API key")) {
                _ = try await collect(try AIProviderRegistry.standard.make(config))
            }
        }
    }

    // An unreachable host is not covered: AsyncHTTPClient keeps retrying the
    // connection until its 60 s deadline before surfacing "connection refused".
    @Test func badAnswersAreTyped() async throws {
        try await withStub("not json") { base, _ in
            let bad = try AIProviderConfig(id: "l", kind: .ollama, name: "L", model: "m", baseURL: base.absoluteString)
            await #expect(throws: AIProviderError.self) { _ = try await collect(try AIProviderRegistry.standard.make(bad)) }
        }
    }

    func stubClaude(_ script: String) throws -> (dir: String, stub: String) {
        let dir = NSTemporaryDirectory() + "claude-stub-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stub = dir + "/claude"
        try ("#!/bin/sh\n" + script).write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
        return (dir, stub)
    }

    @Test func claudeCodeStreamsPartialMessagesThenTheStructuredResult() async throws {
        let (dir, stub) = try stubClaude("""
        printf '%s\\n' "$@" > "$(dirname "$0")/args.txt"
        echo '{"type":"system","subtype":"init"}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\\"title\\":\\"From Cl"}}}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"aude Code\\",\\"priority\\":\\"hi"}}}'
        echo '{"type":"result","is_error":false,"result":"","structured_output":{"title":"From Claude Code","priority":"high","acceptance_criteria":["a"]},"total_cost_usd":0.01,"usage":{"input_tokens":3,"output_tokens":4}}'
        """)
        let config = try AIProviderConfig(id: "cc", kind: .claudeCode, name: "Claude Code", model: "sonnet")
        let events = try await collect(ClaudeCodeProvider(config: config, executable: stub))
        let partials = snapshots(events)
        #expect(partials.map { $0.title } == ["From Cl", "From Claude Code"])
        #expect(partials.last?.priority == nil, "a half-typed enum value is dropped, not guessed")
        guard case let .done(json, _) = try #require(events.last) else { Issue.record("no done event"); return }
        let draft = try TicketDraft.parse(json)
        #expect(draft.title == "From Claude Code")
        #expect(draft.acceptanceCriteria == ["a"])
        #expect(events.contains(.usage(CompletionUsage(inputTokens: 3, outputTokens: 4, costUSD: 0.01))))
        let args = try String(contentsOfFile: dir + "/args.txt", encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(args.contains("stream-json") && args.contains("--include-partial-messages") && args.contains("--verbose"))
        #expect(args.contains("--json-schema"))
        #expect(args.contains("--model") && args.contains("sonnet"))
        #expect(args.contains("--tools"))
        #expect(args.contains("--no-session-persistence"))
        #expect(args.last == "draft")
    }

    @Test func claudeCodeErrorsAreSurfaced() async throws {
        let config = try AIProviderConfig(id: "cc", kind: .claudeCode, name: "CC", model: "sonnet")
        let (dir, notLoggedIn) = try stubClaude("echo '{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in · Please run /login\"}'\n")
        await #expect(throws: AIProviderError.request("Not logged in · Please run /login")) {
            _ = try await collect(ClaudeCodeProvider(config: config, executable: notLoggedIn))
        }
        let (_, crashing) = try stubClaude("echo boom >&2\nexit 3\n")
        await #expect(throws: AIProviderError.request("'\(crashing)' exited with 3: boom\n")) {
            _ = try await collect(ClaudeCodeProvider(config: config, executable: crashing))
        }
        let (_, silent) = try stubClaude("echo '{\"type\":\"system\"}'\n")
        await #expect(throws: AIProviderError.badResponse("claude ended without a result")) {
            _ = try await collect(ClaudeCodeProvider(config: config, executable: silent))
        }
        let (_, slow) = try stubClaude("sleep 5\n")
        await #expect(throws: AIProviderError.unavailable("'\(slow)' timed out after 0s")) {
            _ = try await collect(ClaudeCodeProvider(config: config, executable: slow, timeout: 0.2))
        }
        await #expect(throws: AIProviderError.self) {
            _ = try await collect(ClaudeCodeProvider(config: config, executable: dir + "/missing"))
        }
    }

    @Test func standardRegistryCoversEveryKind() throws {
        let registry = AIProviderRegistry.standard
        #expect(Set(registry.kinds) == Set(AIProviderKind.allCases))
        #expect(try registry.make(AIProviderConfig(id: "x", kind: .claudeCode, name: "x", model: "sonnet")) is ClaudeCodeProvider)
        #expect(try registry.make(AIProviderConfig(id: "x", kind: .apple, name: "x", model: "system")) is AnyLanguageModelProvider)
    }
}
