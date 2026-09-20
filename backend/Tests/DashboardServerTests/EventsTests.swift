import DashboardAPI
import DashboardServer
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import Testing
import Vapor
import VaporTesting
import WebSocketKit

@Suite(.serialized) struct EventsTests {
    @Test func dtoEncodesSnakeCaseKindsAndOptionalProjectId() throws {
        let id = UUID()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try String(decoding: encoder.encode(ChangeEventDTO.hello), as: UTF8.self) == #"{"kind":"hello"}"#)
        let ws = try String(decoding: encoder.encode(ChangeEventDTO(kind: .workspaceChanged, projectId: id)), as: UTF8.self)
        #expect(ws == #"{"kind":"workspace_changed","project_id":"\#(id.uuidString)"}"#)
        #expect(try JSONDecoder().decode(ChangeEventDTO.self, from: Data(#"{"kind":"settings_changed"}"#.utf8)).kind == .settingsChanged)
    }

    /// Runs the app on a real port: the WebSocket handshake needs a live socket.
    func withRunningApp(_ body: (Application, Int, Received) async throws -> Void) async throws {
        let home = try tempDir()
        var environment = Environment.testing
        environment.arguments = ["vapor"]
        let app = try await Application.make(environment)
        do {
            try await configure(app, config: ServerConfig(home: home))
            app.http.server.configuration.hostname = "127.0.0.1"
            app.http.server.configuration.port = 0
            try await app.startup()
            let port = try #require(app.http.server.shared.localAddress?.port)
            let received = Received()
            try await WebSocket.connect(to: "ws://127.0.0.1:\(port)/api/events", on: app.eventLoopGroup) { socket in
                Task { await received.attach(socket) }
                socket.onText { _, text in Task { await received.add(text) } }
            }.get()
            try await received.wait(count: 1)
            try await body(app, port, received)
            await received.close()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    func http(_ method: String, _ port: Int, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func decode(_ frames: [String]) throws -> [ChangeEventDTO] {
        try frames.map { try JSONDecoder().decode(ChangeEventDTO.self, from: Data($0.utf8)) }
    }

    @Test func webSocketStreamsHelloThenMutationsMadeOverHTTP() async throws {
        try await withRunningApp { app, port, received in
            _ = try await http("POST", port, "/api/projects", ["name": "Live", "path": NSTemporaryDirectory() + "live-" + UUID().uuidString])
            try await received.wait(count: 2)
            _ = try await http("PATCH", port, "/api/settings", ["default_storage": "sqlite"])
            try await received.wait(count: 3)
            let frames = try decode(await received.all())
            #expect(frames.map(\.kind) == [.hello, .projectsChanged, .settingsChanged])
            _ = app
        }
    }

    @Test func workspaceMutationsCarryTheProjectId() async throws {
        try await withRunningApp { _, port, received in
            let project = try await http("POST", port, "/api/projects", ["name": "Live", "path": NSTemporaryDirectory() + "live-" + UUID().uuidString])
            let id = try #require(project["id"] as? String)
            try await received.wait(count: 2)
            let base = "/api/projects/\(id)/kanban/v1"
            let boards = try await http("GET", port, "\(base)/boards")
            let boardId = try #require((boards["items"] as? [[String: Any]])?.first?["id"] as? String)
            let columns = try await http("GET", port, "\(base)/boards/\(boardId)/columns")
            let column = try #require((columns["items"] as? [[String: Any]])?.first?["id"] as? String)
            _ = try await http("POST", port, "\(base)/columns/\(column)/cards", ["title": "ping"])
            try await received.wait(count: 3)
            let event = try decode(await received.all())[2]
            #expect(event.kind == .workspaceChanged)
            #expect(event.projectId?.uuidString.lowercased() == id.lowercased())
        }
    }
}

actor Received {
    private var frames: [String] = []
    private var socket: WebSocket?

    func attach(_ socket: WebSocket) { self.socket = socket }
    func close() async { try? await socket?.close() }
    func add(_ frame: String) { frames.append(frame) }
    func all() -> [String] { frames }

    func wait(count: Int) async throws {
        for _ in 0 ..< 100 {
            if frames.count >= count { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Timeout(expected: count, got: frames.count)
    }

    struct Timeout: Error { let expected: Int; let got: Int }
}
