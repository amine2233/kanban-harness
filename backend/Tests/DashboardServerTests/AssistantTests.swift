import DashboardServer
import Foundation
import Testing
import Vapor
import VaporTesting

/// The route is exercised with a stub `claude` executable selected through the
/// claude_code provider, so the whole path (config → provider → parse) runs without network.
@Suite(.serialized) struct AssistantAPITests {
    func stubClaude(output: String) throws -> String {
        let dir = NSTemporaryDirectory() + "claude-stub-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stub = dir + "/claude"
        try "#!/bin/sh\ncat > /dev/null\necho '\(output)'\n".write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
        return stub
    }

    @Test func draftsATicketThroughTheConfiguredClaudeCodeProvider() async throws {
        let stub = try stubClaude(output: #"{"is_error":false,"result":"","structured_output":{"title":"Add password reset","description":"Users forget passwords","acceptance_criteria":["Email sent","Link expires"],"priority":"high","points":5},"total_cost_usd":0.02}"#)
        setenv("MVP_DASHBOARD_CLAUDE_BIN", stub, 1)
        defer { unsetenv("MVP_DASHBOARD_CLAUDE_BIN") }
        try await withServer { app, home in
            let project = try await app.createProject("Demo", at: home + "/demo")
            let id = try #require(project["id"] as? String)
            _ = try await app.json(.PUT, "/api/settings/ai/providers/cc", body: ["kind": "claude_code", "name": "Claude Code", "model": "sonnet"])
            let (_, boards) = try await app.json(.GET, "/api/projects/\(id)/kanban/v1/boards")
            let boardId = try #require(((boards as? [String: Any])?["items"] as? [[String: Any]])?.first?["id"] as? String)

            let (status, body) = try await app.json(.POST, "/api/projects/\(id)/ai/tickets/draft", body: ["idea": "users can't reset their password", "board_id": boardId])
            #expect(status == .ok)
            let response = try #require(body as? [String: Any])
            let draft = try #require(response["draft"] as? [String: Any])
            #expect(draft["title"] as? String == "Add password reset")
            #expect(draft["acceptance_criteria"] as? [String] == ["Email sent", "Link expires"])
            #expect(draft["priority"] as? String == "high")
            #expect(response["provider"] as? String == "cc")
            #expect((response["usage"] as? [String: Any])?["cost_usd"] as? Double == 0.02)

            let (_, cards) = try await app.json(.GET, "/api/projects/\(id)/kanban/v1/boards/\(boardId)/cards")
            #expect((cards as? [String: Any])?["total"] as? Int == 0, "drafting never creates a card by itself")
        }
    }

    @Test func missingProviderAndProviderFailuresUseTheEnvelope() async throws {
        try await withServer { app, home in
            let project = try await app.createProject("Demo", at: home + "/demo")
            let id = try #require(project["id"] as? String)
            let (_, boards) = try await app.json(.GET, "/api/projects/\(id)/kanban/v1/boards")
            let boardId = try #require(((boards as? [String: Any])?["items"] as? [[String: Any]])?.first?["id"] as? String)

            let (none, err) = try await app.json(.POST, "/api/projects/\(id)/ai/tickets/draft", body: ["idea": "x", "board_id": boardId])
            #expect(none == .badRequest)
            #expect((err as? [String: Any])?["code"] as? String == "AI_NOT_CONFIGURED")

            _ = try await app.json(.PUT, "/api/settings/ai/providers/keyless", body: ["kind": "anthropic", "name": "Keyless", "model": "claude-sonnet-5"])
            let (down, downErr) = try await app.json(.POST, "/api/projects/\(id)/ai/tickets/draft", body: ["idea": "x", "board_id": boardId])
            #expect(down == .badGateway)
            #expect((downErr as? [String: Any])?["code"] as? String == "AI_PROVIDER")

            let (unknown, _) = try await app.json(.POST, "/api/projects/\(id)/ai/tickets/draft", body: ["idea": "x", "board_id": boardId, "provider": "ghost"])
            #expect(unknown == .notFound)
            let (empty, _) = try await app.json(.POST, "/api/projects/\(id)/ai/tickets/draft", body: ["idea": "  ", "board_id": boardId])
            #expect(empty == .badRequest)
        }
    }
}
