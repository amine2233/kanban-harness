import DashboardAI
import DashboardDomain
import Foundation
import Testing
import Vapor
@testable import DashboardAIProviders

/// Each HTTP provider is checked against a stub Vapor server that records
/// the request it received and answers in the vendor's shape.
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

    func withStub(_ answer: [String: Any], _ body: (URL, Recorder) async throws -> Void) async throws {
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
            response.headers.contentType = .json
            response.body = .init(data: try JSONSerialization.data(withJSONObject: answer))
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

    @Test func anthropicUsesAForcedToolCall() async throws {
        let answer: [String: Any] = ["model": "claude-sonnet-5", "usage": ["input_tokens": 11, "output_tokens": 22], "content": [["type": "text", "text": "thinking"], ["type": "tool_use", "name": "answer", "input": ["title": "T", "priority": "high"]]]]
        try await withStub(answer) { base, recorder in
            let config = try AIProviderConfig(id: "a", kind: .anthropic, name: "A", model: "claude-sonnet-5", baseURL: base.absoluteString, apiKey: "sk-a")
            let result = try await AnthropicProvider(config: config).complete(request)
            #expect(try TicketDraft.parse(result.json).title == "T")
            #expect(result.usage == CompletionUsage(inputTokens: 11, outputTokens: 22))
            let sent = try #require(await recorder.first())
            #expect(sent.path == "/v1/messages")
            #expect(sent.headers["x-api-key"] == "sk-a")
            #expect(sent.headers["anthropic-version"] != nil)
            #expect(sent.body["system"] as? String == "sys")
            #expect((sent.body["tool_choice"] as? [String: Any])?["name"] as? String == "answer")
            #expect(sent.body["max_tokens"] as? Int == 300)
        }
    }

    @Test func anthropicWithoutKeyIsNotConfigured() async throws {
        let config = try AIProviderConfig(id: "a", kind: .anthropic, name: "A", model: "m")
        await #expect(throws: AIProviderError.notConfigured("A has no API key")) {
            try await AnthropicProvider(config: config).complete(request)
        }
    }

    @Test func openAICompatibleUsesJSONSchemaResponseFormat() async throws {
        let answer: [String: Any] = ["model": "gpt-x", "usage": ["prompt_tokens": 5, "completion_tokens": 6], "choices": [["message": ["role": "assistant", "content": "```json\n{\"title\":\"From OpenAI\",\"priority\":\"low\"}\n```"]]]]
        try await withStub(answer) { base, recorder in
            let config = try AIProviderConfig(id: "o", kind: .openaiCompatible, name: "O", model: "gpt-x", baseURL: base.absoluteString + "/v1", apiKey: "sk-o")
            let result = try await OpenAICompatibleProvider(config: config).complete(request)
            #expect(try TicketDraft.parse(result.json).title == "From OpenAI")
            let sent = try #require(await recorder.first())
            #expect(sent.path == "/v1/chat/completions")
            #expect(sent.headers["authorization"] == "Bearer sk-o")
            #expect(((sent.body["response_format"] as? [String: Any])?["type"] as? String) == "json_schema")
            #expect((sent.body["messages"] as? [[String: Any]])?.first?["role"] as? String == "system")
        }
    }

    @Test func ollamaSendsTheSchemaAsFormat() async throws {
        let answer: [String: Any] = ["model": "llama3.2", "prompt_eval_count": 7, "eval_count": 8, "message": ["role": "assistant", "content": "{\"title\":\"Local\",\"priority\":\"medium\"}"]]
        try await withStub(answer) { base, recorder in
            let config = try AIProviderConfig(id: "l", kind: .ollama, name: "L", model: "llama3.2", baseURL: base.absoluteString)
            let result = try await OllamaProvider(config: config).complete(request)
            #expect(try TicketDraft.parse(result.json).title == "Local")
            #expect(result.usage.inputTokens == 7)
            let sent = try #require(await recorder.first())
            #expect(sent.path == "/api/chat")
            #expect(sent.headers["authorization"] == nil)
            #expect((sent.body["format"] as? [String: Any])?["type"] as? String == "object")
            #expect(sent.body["stream"] as? Bool == false)
        }
    }

    @Test func httpErrorsAndUnreachableHostsAreTyped() async throws {
        let config = try AIProviderConfig(id: "l", kind: .ollama, name: "L", model: "m", baseURL: "http://127.0.0.1:1")
        do {
            _ = try await OllamaProvider(config: config).complete(request)
            Issue.record("expected error")
        } catch let error as AIProviderError {
            if case .unavailable = error {} else { Issue.record("unexpected \(error)") }
        }
        try await withStub(["error": "nope"]) { base, _ in
            let bad = try AIProviderConfig(id: "l", kind: .ollama, name: "L", model: "m", baseURL: base.absoluteString)
            await #expect(throws: AIProviderError.self) { try await OllamaProvider(config: bad).complete(request) }
        }
    }

    @Test func claudeCodeRunsTheCLIHeadlessAndReadsStructuredOutput() async throws {
        let dir = NSTemporaryDirectory() + "claude-stub-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stub = dir + "/claude"
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(dir)/args.txt"
        echo '{"type":"result","is_error":false,"result":"{\\"title\\":\\"From Claude Code\\",\\"priority\\":\\"high\\"}","structured_output":{"title":"From Claude Code","priority":"high","acceptance_criteria":["a"]},"total_cost_usd":0.01,"usage":{"input_tokens":3,"output_tokens":4}}'
        """.write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
        let config = try AIProviderConfig(id: "cc", kind: .claudeCode, name: "Claude Code", model: "sonnet")
        let result = try await ClaudeCodeProvider(config: config, executable: stub).complete(request)
        let draft = try TicketDraft.parse(result.json)
        #expect(draft.title == "From Claude Code")
        #expect(draft.acceptanceCriteria == ["a"])
        #expect(result.usage.costUSD == 0.01)
        let args = try String(contentsOfFile: dir + "/args.txt", encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(args.contains("--json-schema"))
        #expect(args.contains("--model") && args.contains("sonnet"))
        #expect(args.contains("--tools"))
        #expect(args.contains("--no-session-persistence"))
        #expect(args.last == "draft")
    }

    @Test func claudeCodeErrorsAreSurfaced() async throws {
        let dir = NSTemporaryDirectory() + "claude-stub-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let notLoggedIn = dir + "/claude"
        try "#!/bin/sh\necho '{\"is_error\":true,\"result\":\"Not logged in · Please run /login\"}'\n".write(toFile: notLoggedIn, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notLoggedIn)
        let config = try AIProviderConfig(id: "cc", kind: .claudeCode, name: "CC", model: "sonnet")
        await #expect(throws: AIProviderError.request("Not logged in · Please run /login")) {
            try await ClaudeCodeProvider(config: config, executable: notLoggedIn).complete(request)
        }
        await #expect(throws: AIProviderError.self) {
            try await ClaudeCodeProvider(config: config, executable: dir + "/missing").complete(request)
        }
    }

    @Test func standardRegistryCoversEveryKind() throws {
        let registry = AIProviderRegistry.standard
        #expect(Set(registry.kinds) == Set(AIProviderKind.allCases))
        #expect(try registry.make(AIProviderConfig(id: "x", kind: .claudeCode, name: "x", model: "sonnet")) is ClaudeCodeProvider)
    }
}
