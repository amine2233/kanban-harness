import DashboardAPI
import DashboardServer
import Foundation
import Testing
import Vapor
import VaporTesting

func tempDir() throws -> String {
    let path = NSTemporaryDirectory() + "mvp-dashboard-server-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

func withServer(_ body: (TestingApplicationTester, String) async throws -> Void) async throws {
    let home = try tempDir()
    try await withApp(configure: { app in
        try await configure(app, config: ServerConfig(home: home))
    }) { app in
        try await body(try app.testing(), home)
    }
}

extension TestingApplicationTester {
    func json(_ method: HTTPMethod, _ path: String, body: [String: Any]? = nil) async throws -> (HTTPStatus, Any?) {
        var headers = HTTPHeaders()
        var buffer: ByteBuffer? = nil
        if let body {
            headers.contentType = .json
            buffer = ByteBuffer(data: try JSONSerialization.data(withJSONObject: body))
        }
        let response = try await sendRequest(method, path, headers: headers, body: buffer)
        let data = Data(buffer: response.body)
        let parsed = data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data)
        return (response.status, parsed)
    }

    func createProject(_ name: String, at path: String) async throws -> [String: Any] {
        let (status, body) = try await json(.POST, "/api/projects", body: ["name": name, "path": path])
        #expect(status == .created)
        return try #require(body as? [String: Any])
    }

    func firstBoardAndColumns(_ base: String) async throws -> (String, [[String: Any]]) {
        let (_, boards) = try await json(.GET, "\(base)/boards")
        let boardId = try #require(((boards as? [String: Any])?["items"] as? [[String: Any]])?.first?["id"] as? String)
        let (_, columns) = try await json(.GET, "\(base)/boards/\(boardId)/columns")
        return (boardId, try #require((columns as? [String: Any])?["items"] as? [[String: Any]]))
    }
}

@Suite(.serialized) struct ApiTests {
    @Test func healthReturnsOk() async throws {
        try await withServer { app, _ in
            let (status, body) = try await app.json(.GET, "/api/health")
            #expect(status == .ok)
            #expect((body as? [String: Any])?["status"] as? String == "ok")
        }
    }

    @Test func listProjectsStartsEmpty() async throws {
        try await withServer { app, _ in
            let (status, body) = try await app.json(.GET, "/api/projects")
            #expect(status == .ok)
            #expect((body as? [Any])?.isEmpty == true)
        }
    }

    @Test func createProjectReturns201AndListsIt() async throws {
        try await withServer { app, home in
            let created = try await app.createProject("Demo", at: home + "/demo")
            #expect(created["name"] as? String == "Demo")
            #expect(created["storage"] as? String == "json")
            let (_, listed) = try await app.json(.GET, "/api/projects")
            let items = try #require(listed as? [[String: Any]])
            #expect(items.count == 1)
            #expect(items[0]["id"] as? String == created["id"] as? String)
            #expect(FileManager.default.fileExists(atPath: home + "/demo/kanban.json"))
        }
    }

    @Test func createProjectWithInvalidBodyReturns400Envelope() async throws {
        try await withServer { app, _ in
            let (status, body) = try await app.json(.POST, "/api/projects", body: ["name": "x"])
            #expect(status == .badRequest)
            #expect((body as? [String: Any])?["code"] as? String == "VALIDATION_FAILED")
        }
    }

    @Test func createProjectWithRelativePathReturns400() async throws {
        try await withServer { app, _ in
            let (status, _) = try await app.json(.POST, "/api/projects", body: ["name": "x", "path": "relative"])
            #expect(status == .badRequest)
        }
    }

    @Test func createDuplicateProjectReturns409() async throws {
        try await withServer { app, home in
            _ = try await app.createProject("Demo", at: home + "/a")
            let (status, body) = try await app.json(.POST, "/api/projects", body: ["name": "demo", "path": home + "/b"])
            #expect(status == .conflict)
            #expect((body as? [String: Any])?["code"] as? String == "ALREADY_EXISTS")
        }
    }

    @Test func getUnknownProjectReturns404() async throws {
        try await withServer { app, _ in
            let (status, body) = try await app.json(.GET, "/api/projects/\(UUID().uuidString)")
            #expect(status == .notFound)
            #expect((body as? [String: Any])?["code"] as? String == "NOT_FOUND")
        }
    }

    @Test func deleteProjectReturns204Then404AndKeepsFiles() async throws {
        try await withServer { app, home in
            let id = try #require(try await app.createProject("Demo", at: home + "/demo")["id"] as? String)
            #expect(try await app.json(.DELETE, "/api/projects/\(id)").0 == .noContent)
            #expect(try await app.json(.GET, "/api/projects/\(id)").0 == .notFound)
            #expect(FileManager.default.fileExists(atPath: home + "/demo/kanban.json"))
        }
    }

    @Test func registryPersistsAcrossRestarts() async throws {
        let home = try tempDir()
        try await withApp(configure: { try await configure($0, config: ServerConfig(home: home)) }) { app in
            _ = try await app.testing().createProject("Persist", at: home + "/p")
        }
        try await withApp(configure: { try await configure($0, config: ServerConfig(home: home)) }) { app in
            let (_, listed) = try await app.testing().json(.GET, "/api/projects")
            #expect((listed as? [[String: Any]])?.first?["name"] as? String == "Persist")
        }
    }

    @Test func kanbanListsSeededBoardAndColumns() async throws {
        try await withServer { app, home in
            let id = try #require(try await app.createProject("Demo", at: home + "/demo")["id"] as? String)
            let base = "/api/projects/\(id)/kanban/v1"
            let (status, boards) = try await app.json(.GET, "\(base)/boards")
            #expect(status == .ok)
            let page = try #require(boards as? [String: Any])
            #expect(page["total"] as? Int == 1)
            #expect(page["page_size"] as? Int == 50)
            let board = try #require((page["items"] as? [[String: Any]])?.first)
            #expect(board["name"] as? String == "Demo")
            #expect(board["task_list_view"] as? String == "flat")
            let (_, columns) = try await app.firstBoardAndColumns(base)
            #expect(columns.map { $0["name"] as? String } == ["TODO", "Doing", "Complete"])
            #expect(columns.map { $0["default_status"] as? String } == ["todo", "in_progress", "done"])
        }
    }

    @Test func kanbanCardLifecycleCreateMoveUpdateDelete() async throws {
        try await withServer { app, home in
            let id = try #require(try await app.createProject("Demo", at: home + "/demo")["id"] as? String)
            let base = "/api/projects/\(id)/kanban/v1"
            let (boardId, columns) = try await app.firstBoardAndColumns(base)
            let todo = try #require(columns[0]["id"] as? String)
            let done = try #require(columns[2]["id"] as? String)

            let (created, card) = try await app.json(.POST, "\(base)/columns/\(todo)/cards", body: ["title": "Ship it", "priority": "high"])
            #expect(created == .created)
            let cardBody = try #require(card as? [String: Any])
            #expect(cardBody["title"] as? String == "Ship it")
            #expect(cardBody["priority"] as? String == "high")
            #expect(cardBody["status"] as? String == "todo")
            #expect(cardBody["card_number"] as? Int == 1)
            let cardId = try #require(cardBody["id"] as? String)

            let (moved, movedBody) = try await app.json(.PATCH, "\(base)/boards/\(boardId)/cards/\(cardId)", body: ["column_id": done])
            #expect(moved == .ok)
            #expect((movedBody as? [String: Any])?["status"] as? String == "done")
            #expect((movedBody as? [String: Any])?["completed_at"] is String)

            let (updated, updatedBody) = try await app.json(.PATCH, "\(base)/boards/\(boardId)/cards/\(cardId)", body: ["title": "Shipped", "description": NSNull()])
            #expect(updated == .ok)
            #expect((updatedBody as? [String: Any])?["title"] as? String == "Shipped")

            let raw = try String(contentsOfFile: home + "/demo/kanban.json", encoding: .utf8)
            #expect(raw.contains("Shipped"), "card must be saved to the project file")

            #expect(try await app.json(.DELETE, "\(base)/boards/\(boardId)/cards/\(cardId)").0 == .noContent)
            let (_, cards) = try await app.json(.GET, "\(base)/boards/\(boardId)/cards")
            #expect((cards as? [String: Any])?["total"] as? Int == 0)
        }
    }

    @Test func kanbanRejectsBadPriorityAndUnknownCards() async throws {
        try await withServer { app, home in
            let id = try #require(try await app.createProject("Demo", at: home + "/demo")["id"] as? String)
            let base = "/api/projects/\(id)/kanban/v1"
            let (boardId, columns) = try await app.firstBoardAndColumns(base)
            let todo = try #require(columns[0]["id"] as? String)
            #expect(try await app.json(.POST, "\(base)/columns/\(todo)/cards", body: ["title": "x", "priority": "urgent"]).0 == .badRequest)
            #expect(try await app.json(.POST, "\(base)/columns/\(todo)/cards", body: ["title": "   "]).0 == .badRequest)
            #expect(try await app.json(.POST, "\(base)/columns/\(UUID().uuidString)/cards", body: ["title": "x"]).0 == .notFound)
            #expect(try await app.json(.DELETE, "\(base)/boards/\(boardId)/cards/\(UUID().uuidString)").0 == .notFound)
        }
    }

    @Test func kanbanForUnknownProjectReturns404() async throws {
        try await withServer { app, _ in
            let (status, _) = try await app.json(.GET, "/api/projects/\(UUID().uuidString)/kanban/v1/boards")
            #expect(status == .notFound)
        }
    }

    @Test func staticDirServesSpaFallback() async throws {
        let home = try tempDir()
        let dist = home + "/dist"
        try FileManager.default.createDirectory(atPath: dist, withIntermediateDirectories: true)
        try "<h1>app</h1>".write(toFile: dist + "/index.html", atomically: true, encoding: .utf8)
        try await withApp(configure: { try await configure($0, config: ServerConfig(home: home, staticDir: dist)) }) { app in
            let index = try await app.testing().sendRequest(.GET, "/")
            #expect(index.status == .ok)
            let deep = try await app.testing().sendRequest(.GET, "/projects/abc")
            #expect(deep.status == .ok)
            #expect(deep.body.string.contains("<h1>app</h1>"))
            #expect(try await app.testing().json(.GET, "/api/projects").0 == .ok)
        }
    }
}
