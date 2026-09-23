import DashboardServer
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite(.serialized)
struct MCPHTTPTests {
    func rpc(
        _ app: TestingApplicationTester,
        _ body: [String: Any]
    ) async throws -> (HTTPStatus, [String: Any]) {
        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.add(name: .accept, value: "application/json")
        headers.add(name: "MCP-Protocol-Version", value: "2025-06-18")
        let response = try await app.sendRequest(
            .POST,
            "/mcp",
            headers: headers,
            body: ByteBuffer(data: JSONSerialization.data(withJSONObject: body))
        )
        let data = Data(buffer: response.body)
        let json = try data
            .isEmpty ? [:] : ((JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        return (response.status, json)
    }

    @Test
    func mcpOverHTTPListsAndCallsTools() async throws {
        try await withServer { app, home in
            let project = try await app.createProject("Demo", at: home + "/demo")
            let (initStatus, initBody) = try await rpc(
                app,
                [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": [
                        "protocolVersion": "2025-06-18",
                        "capabilities": [:],
                        "clientInfo": ["name": "test", "version": "1"]
                    ]
                ]
            )
            #expect(initStatus == .ok)
            #expect(
                ((initBody["result"] as? [
                    String: Any
                ])?["serverInfo"] as? [String: Any])?["name"] as? String ==
                    "mvp-dashboard"
            )

            let (_, list) = try await rpc(app, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
            let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
            #expect(tools.contains { $0["name"] as? String == "create_card" })

            let (_, call) = try await rpc(
                app,
                [
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": [
                        "name": "create_card",
                        "arguments": ["project": "Demo", "board": "Demo", "title": "From MCP over HTTP"]
                    ]
                ]
            )
            let result = try #require(call["result"] as? [String: Any])
            #expect(result["isError"] as? Bool == false)
            #expect((result["structuredContent"] as? [String: Any])?["key"] as? String == "task-1")

            let id = try #require(project["id"] as? String)
            let (_, boards) = try await app.json(.GET, "/api/projects/\(id)/kanban/v1/boards")
            let boardId = try #require(((boards as? [String: Any])?["items"] as? [[String: Any]])?
                .first?["id"] as? String)
            let (_, cards) = try await app.json(.GET, "/api/projects/\(id)/kanban/v1/boards/\(boardId)/cards")
            #expect(
                (cards as? [String: Any])?["total"] as? Int == 1,
                "the card is visible through the REST API too"
            )
        }
    }

    @Test
    func mcpRejectsNonPostAndBadOrigins() async throws {
        try await withServer { app, _ in
            #expect(try await app.sendRequest(.GET, "/mcp").status == .methodNotAllowed)
            var headers = HTTPHeaders()
            headers.contentType = .json
            headers.add(name: .accept, value: "application/json")
            headers.add(name: .origin, value: "http://evil.example")
            let response = try await app.sendRequest(
                .POST,
                "/mcp",
                headers: headers,
                body: ByteBuffer(string: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
            )
            #expect(response.status == .forbidden)
        }
    }
}
