import DashboardDomain
import DashboardPersistence
import DashboardService
import Foundation
import MCP
import Testing
@testable import DashboardMCP

/// A real MCP client talking to the real server over an in-memory transport,
/// backed by in-memory stores: the whole tool path minus I/O and networking.
@Suite(.serialized)
struct KanbanToolsTests {
    actor Workspaces {
        private var stores: [String: WorkspaceStoreInMemory] = [:]
        func store(_ project: Project) -> WorkspaceStoreInMemory {
            if let s = stores[project.path] { return s }
            let s = WorkspaceStoreInMemory()
            stores[project.path] = s
            return s
        }
    }

    struct Lazy: WorkspaceStore {
        let project: Project
        let workspaces: Workspaces
        func load() async throws -> Workspace {
            try await workspaces.store(project).load()
        }

        func save(_ w: Workspace) async throws {
            try await workspaces.store(project).save(w)
        }
    }

    func connectedClient() async throws -> (Client, Server, String) {
        let workspaces = Workspaces()
        let projects = ProjectService(
            store: ProjectStoreInMemory(),
            workspaces: WorkspaceStoreFactory { Lazy(project: $0, workspaces: workspaces) }
        )
        let settings = SettingsService(store: SettingsStoreInMemory())
        let folder = NSTemporaryDirectory() + "mcp-" + UUID().uuidString
        _ = try await projects.add(name: "Demo", path: folder, storage: .json)
        let server = await DashboardMCPServer.make(
            projects: LocalProjectCommands(projects: projects, settings: settings),
            boards: LocalBoardCommands(projects: projects)
        )
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: serverTransport)
        let client = Client(name: "test", version: "1")
        _ = try await client.connect(transport: clientTransport)
        return (client, server, folder)
    }

    /// Parses the text content; list results come back as `{items, count}`, so `items` is unwrapped.
    func text(_ result: (content: [Tool.Content], isError: Bool?)) throws -> Any {
        guard case let .text(text, _, _)? = result.content.first else { throw ToolError("no text") }

        let value = try JSONSerialization.jsonObject(with: Data(text.utf8))
        if let object = value as? [String: Any], let items = object["items"], object.keys.sorted() == [
            "count",
            "items"
        ] { return items }
        return value
    }

    @Test
    func listsAllToolsWithSchemas() async throws {
        let (client, server, _) = try await connectedClient()
        let (tools, _) = try await client.listTools()
        #expect(tools.map(\.name).sorted() == [
            "create_board",
            "create_card",
            "create_subtasks",
            "delete_card",
            "list_boards",
            "list_card_children",
            "list_cards",
            "list_columns",
            "list_projects",
            "move_card",
            "remove_card_parent",
            "set_card_parent",
            "update_card"
        ])
        let create = try #require(tools.first { $0.name == "create_card" })
        #expect(create.inputSchema.objectValue?["required"]?.arrayValue?.map(\.stringValue) == [
            "project",
            "board",
            "title"
        ])
        await server.stop()
    }

    @Test
    func fullCardLifecycleThroughTools() async throws {
        let (client, server, _) = try await connectedClient()

        let projects =
            try #require(try await text(client.callTool(name: "list_projects")) as? [[String: Any]])
        #expect(projects.map { $0["name"] as? String } == ["Demo"])

        let boards = try #require(try await text(client.callTool(
            name: "list_boards",
            arguments: ["project": "demo"]
        )) as? [[String: Any]])
        #expect(boards.first?["name"] as? String == "Demo")

        let columns = try #require(try await text(client.callTool(
            name: "list_columns",
            arguments: ["project": "Demo", "board": "Demo"]
        )) as? [[String: Any]])
        #expect(columns.map { $0["name"] as? String } == ["Backlog", "To do", "In progress", "Done"])

        let created = try #require(try await text(client.callTool(name: "create_card", arguments: [
            "project": "Demo", "board": "demo", "column": "to do", "title": "Write MCP tests",
            "priority": "high",
            "description": "via MCP"
        ])) as? [String: Any])
        #expect(created["key"] as? String == "task-1")
        #expect(created["column"] as? String == "To do")
        #expect(created["status"] as? String == "todo")

        let moved = try #require(try await text(client.callTool(
            name: "move_card",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-1", "column": "Done"]
        )) as? [String: Any])
        #expect(moved["status"] as? String == "done")
        #expect(moved["column"] as? String == "Done")

        let updated = try #require(try await text(client.callTool(
            name: "update_card",
            arguments: [
                "project": "Demo",
                "board": "Demo",
                "card": "1",
                "title": "Renamed",
                "points": 3,
                "due_date": "2026-12-24",
                "description": ""
            ]
        )) as? [String: Any])
        #expect(updated["title"] as? String == "Renamed")
        #expect(updated["points"] as? Int == 3)
        #expect((updated["due_date"] as? String)?.hasPrefix("2026-12-24") == true)
        #expect(updated["description"] == nil || updated["description"] is NSNull, "cleared description")

        let done = try #require(try await text(client.callTool(
            name: "list_cards",
            arguments: ["project": "Demo", "board": "Demo", "status": "done"]
        )) as? [[String: Any]])
        #expect(done.count == 1)
        let backlog = try #require(try await text(client.callTool(
            name: "list_cards",
            arguments: ["project": "Demo", "board": "Demo", "column": "Backlog"]
        )) as? [[String: Any]])
        #expect(backlog.isEmpty)

        let createdId = try #require(created["id"] as? String)
        let deleted = try #require(try await text(client.callTool(
            name: "delete_card",
            arguments: ["project": "Demo", "board": "Demo", "card": .string(createdId)]
        )) as? [String: Any])
        #expect(deleted["key"] as? String == "task-1")
        let remaining = try #require(try await text(client.callTool(
            name: "list_cards",
            arguments: ["project": "Demo", "board": "Demo"]
        )) as? [[String: Any]])
        #expect(remaining.isEmpty)
        await server.stop()
    }

    @Test
    func subtaskToolsBuildAndWalkTheHierarchy() async throws {
        let (client, server, _) = try await connectedClient()
        let parent = try #require(try await text(client.callTool(
            name: "create_card",
            arguments: ["project": "Demo", "board": "Demo", "title": "Epic"]
        )) as? [String: Any])
        let children = try #require(try await text(client.callTool(name: "create_subtasks", arguments: [
            "project": "Demo", "board": "Demo", "card": "task-1",
            "subtasks": [["title": "One", "points": 2], ["title": "Two", "priority": "low"]]
        ])) as? [[String: Any]])
        #expect(children.map { $0["title"] as? String } == ["One", "Two"])
        #expect(children[0]["points"] as? Int == 2)
        #expect(children.allSatisfy { $0["column"] as? String == "Backlog" })

        #expect(parent["key"] as? String == "task-1")
        let listed = try #require(try await text(client.callTool(
            name: "list_card_children",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-1"]
        )) as? [[String: Any]])
        #expect(listed.count == 2)
        _ = try await client.callTool(
            name: "remove_card_parent",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-2"]
        )
        #expect(try #require(try await text(client.callTool(
            name: "list_card_children",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-1"]
        )) as? [[String: Any]]).count == 1)
        _ = try await client.callTool(
            name: "set_card_parent",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-2", "parent": "task-1"]
        )
        #expect(try #require(try await text(client.callTool(
            name: "list_card_children",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-1"]
        )) as? [[String: Any]]).count == 2)
        let cycle = try await client.callTool(
            name: "set_card_parent",
            arguments: ["project": "Demo", "board": "Demo", "card": "task-1", "parent": "task-2"]
        )
        #expect(cycle.isError == true)
        await server.stop()
    }

    @Test
    func createBoardWithAndWithoutColumns() async throws {
        let (client, server, _) = try await connectedClient()
        let seeded = try #require(try await text(client.callTool(
            name: "create_board",
            arguments: ["project": "Demo", "name": "Roadmap"]
        )) as? [String: Any])
        #expect(seeded["position"] as? Int == 1)
        let cols = try #require(try await text(client.callTool(
            name: "list_columns",
            arguments: ["project": "Demo", "board": "Roadmap"]
        )) as? [[String: Any]])
        #expect(cols.count == 4)
        _ = try await client.callTool(
            name: "create_board",
            arguments: ["project": "Demo", "name": "Bare", "with_default_columns": false]
        )
        let bare = try #require(try await text(client.callTool(
            name: "list_columns",
            arguments: ["project": "Demo", "board": "Bare"]
        )) as? [[String: Any]])
        #expect(bare.isEmpty)
        await server.stop()
    }

    @Test
    func errorsAreReportedAsToolErrorsNotProtocolErrors() async throws {
        let (client, server, _) = try await connectedClient()
        let missing = try await client.callTool(name: "list_boards", arguments: ["project": "ghost"])
        #expect(missing.isError == true)
        if case let .text(text, _, _)? = missing.content.first {
            #expect(text.contains("not found"))
        } else {
            Issue.record("no text")
        }

        let badArgs = try await client.callTool(
            name: "create_card",
            arguments: ["project": "Demo", "board": "Demo"]
        )
        #expect(badArgs.isError == true)
        let badPriority = try await client.callTool(
            name: "create_card",
            arguments: ["project": "Demo", "board": "Demo", "title": "x", "priority": "urgent"]
        )
        #expect(badPriority.isError == true)
        let unknownTool = try await client.callTool(name: "explode")
        #expect(unknownTool.isError == true)
        await server.stop()
    }

    @Test
    func cardReferencesAcceptIdNumberAndKey() throws {
        let board = UUID()
        let card = Card(
            boardId: board,
            columnId: UUID(),
            prefix: "KAN",
            cardNumber: 7,
            title: "t",
            position: 0
        )
        #expect(try KanbanToolDispatcher.findCard([card], "7").id == card.id)
        #expect(try KanbanToolDispatcher.findCard([card], "kan-7").id == card.id)
        #expect(try KanbanToolDispatcher.findCard([card], card.id.uuidString).id == card.id)
        #expect(throws: ToolError.self) { try KanbanToolDispatcher.findCard([card], "task-7") }
        #expect(throws: ToolError.self) { try KanbanToolDispatcher.findCard([card], "8") }
    }
}
