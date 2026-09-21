import DashboardServer
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite(.serialized) struct KanbanManagementTests {
    func project(_ app: TestingApplicationTester, _ home: String) async throws -> String {
        let id = try #require(try await app.createProject("Demo", at: home + "/demo")["id"] as? String)
        return "/api/projects/\(id)/kanban/v1"
    }

    @Test func createRenameReorderAndDeleteBoards() async throws {
        try await withServer { app, home in
            let base = try await project(app, home)
            let (status, created) = try await app.json(.POST, "\(base)/boards", body: ["name": "Second", "card_prefix": "SEC"])
            #expect(status == .created)
            let second = try #require(created as? [String: Any])
            #expect(second["card_prefix"] as? String == "SEC")
            let secondId = try #require(second["id"] as? String)
            let (_, columns) = try await app.json(.GET, "\(base)/boards/\(secondId)/columns")
            #expect(((columns as? [String: Any])?["items"] as? [Any])?.count == 4, "default columns seeded")

            let (_, bare) = try await app.json(.POST, "\(base)/boards", body: ["name": "Bare", "with_default_columns": false])
            let bareId = try #require((bare as? [String: Any])?["id"] as? String)
            let (_, bareColumns) = try await app.json(.GET, "\(base)/boards/\(bareId)/columns")
            #expect(((bareColumns as? [String: Any])?["total"] as? Int) == 0)

            let (renamed, body) = try await app.json(.PATCH, "\(base)/boards/\(secondId)", body: ["name": "Renamed", "position": 0, "description": "desc"])
            #expect(renamed == .ok)
            #expect((body as? [String: Any])?["name"] as? String == "Renamed")
            #expect((body as? [String: Any])?["position"] as? Int == 0)
            let (_, list) = try await app.json(.GET, "\(base)/boards")
            let names = ((list as? [String: Any])?["items"] as? [[String: Any]])?.map { $0["name"] as? String }
            #expect(names == ["Renamed", "Demo", "Bare"])

            #expect(try await app.json(.DELETE, "\(base)/boards/\(bareId)").0 == .noContent)
            #expect(try await app.json(.GET, "\(base)/boards/\(bareId)/columns").0 == .notFound)
            #expect(try await app.json(.PATCH, "\(base)/boards/\(secondId)", body: ["name": " "]).0 == .badRequest)
            #expect(try await app.json(.POST, "\(base)/boards", body: ["name": ""]).0 == .badRequest)
        }
    }

    @Test func cloneBoardCopiesColumnsAndCards() async throws {
        try await withServer { app, home in
            let base = try await project(app, home)
            let (boardId, columns) = try await app.firstBoardAndColumns(base)
            let doing = try #require(columns[1]["id"] as? String)
            _ = try await app.json(.POST, "\(base)/columns/\(doing)/cards", body: ["title": "Original", "priority": "critical"])

            let (status, clone) = try await app.json(.POST, "\(base)/boards/\(boardId)/clone", body: ["name": "Copy"])
            #expect(status == .created)
            let cloneId = try #require((clone as? [String: Any])?["id"] as? String)
            #expect((clone as? [String: Any])?["name"] as? String == "Copy")
            let (_, cards) = try await app.json(.GET, "\(base)/boards/\(cloneId)/cards")
            let items = try #require((cards as? [String: Any])?["items"] as? [[String: Any]])
            #expect(items.map { $0["title"] as? String } == ["Original"])
            #expect(items[0]["priority"] as? String == "critical")
            #expect(items[0]["card_number"] as? Int == 2)
            let (_, defaultName) = try await app.json(.POST, "\(base)/boards/\(boardId)/clone")
            #expect((defaultName as? [String: Any])?["name"] as? String == "Demo copy")
        }
    }

    @Test func columnLifecycleCreateUpdateReorderDelete() async throws {
        try await withServer { app, home in
            let base = try await project(app, home)
            let (boardId, columns) = try await app.firstBoardAndColumns(base)
            let (status, created) = try await app.json(.POST, "\(base)/boards/\(boardId)/columns", body: ["name": "Review", "wip_limit": 2, "default_status": "blocked"])
            #expect(status == .created)
            let review = try #require(created as? [String: Any])
            #expect(review["position"] as? Int == 4)
            #expect(review["default_status"] as? String == "blocked")
            let reviewId = try #require(review["id"] as? String)

            let (updated, body) = try await app.json(.PATCH, "\(base)/boards/\(boardId)/columns/\(reviewId)", body: ["name": "QA", "position": 1, "wip_limit": NSNull(), "default_status": "in_progress"])
            #expect(updated == .ok)
            let qa = try #require(body as? [String: Any])
            #expect(qa["name"] as? String == "QA")
            #expect(qa["position"] as? Int == 1)
            #expect(qa["wip_limit"] is NSNull)
            #expect(qa["default_status"] as? String == "in_progress")

            let (_, list) = try await app.json(.GET, "\(base)/boards/\(boardId)/columns")
            let names = ((list as? [String: Any])?["items"] as? [[String: Any]])?.map { $0["name"] as? String }
            #expect(names == ["Backlog", "QA", "To do", "In progress", "Done"])

            let todo = try #require(columns[0]["id"] as? String)
            _ = try await app.json(.POST, "\(base)/columns/\(todo)/cards", body: ["title": "doomed"])
            #expect(try await app.json(.DELETE, "\(base)/boards/\(boardId)/columns/\(todo)").0 == .noContent)
            let (_, cards) = try await app.json(.GET, "\(base)/boards/\(boardId)/cards")
            #expect((cards as? [String: Any])?["total"] as? Int == 0)
            #expect(try await app.json(.POST, "\(base)/boards/\(boardId)/columns", body: ["name": "x", "default_status": "weird"]).0 == .badRequest)
            #expect(try await app.json(.DELETE, "\(base)/boards/\(boardId)/columns/\(UUID().uuidString)").0 == .notFound)
        }
    }

    @Test func moveCardToAnotherBoardAndPatchExtraFields() async throws {
        try await withServer { app, home in
            let base = try await project(app, home)
            let (boardId, columns) = try await app.firstBoardAndColumns(base)
            let todo = try #require(columns[0]["id"] as? String)
            let (_, card) = try await app.json(.POST, "\(base)/columns/\(todo)/cards", body: ["title": "Traveller"])
            let cardId = try #require((card as? [String: Any])?["id"] as? String)
            let (_, other) = try await app.json(.POST, "\(base)/boards", body: ["name": "Other", "card_prefix": "OTH"])
            let otherId = try #require((other as? [String: Any])?["id"] as? String)

            let (status, moved) = try await app.json(.PATCH, "\(base)/boards/\(boardId)/cards/\(cardId)", body: ["board_id": otherId, "points": 3, "due_date": "2026-12-01T00:00:00Z"])
            #expect(status == .ok)
            let body = try #require(moved as? [String: Any])
            #expect(body["board_id"] as? String == otherId.lowercased() || body["board_id"] as? String == otherId)
            #expect(body["prefix"] as? String == "OTH")
            #expect(body["card_number"] as? Int == 1)
            #expect(body["points"] as? Int == 3)
            #expect((body["due_date"] as? String)?.hasPrefix("2026-12-01") == true)

            #expect(try await app.json(.GET, "\(base)/boards/\(boardId)/cards").1.flatMap { ($0 as? [String: Any])?["total"] as? Int } == 0)
            let (_, otherCards) = try await app.json(.GET, "\(base)/boards/\(otherId)/cards")
            #expect((otherCards as? [String: Any])?["total"] as? Int == 1)
            #expect(try await app.json(.PATCH, "\(base)/boards/\(boardId)/cards/\(cardId)", body: ["title": "gone"]).0 == .notFound, "card no longer belongs to the old board")
        }
    }
}
