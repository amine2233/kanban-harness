import DashboardDomain
import DashboardServer
import DashboardService
import Foundation
import Testing
import Vapor
@testable import DashboardClient

/// The client is exercised against a real running server so both ends of the wire are covered.
@Suite(.serialized) struct ClientTests {
    func withServer(_ body: (DashboardClient, String) async throws -> Void) async throws {
        let home = NSTemporaryDirectory() + "mvp-dashboard-client-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        var environment = Environment.testing
        environment.arguments = ["vapor"]
        let app = try await Application.make(environment)
        do {
            try await configure(app, config: ServerConfig(home: home))
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

    @Test func reachabilityReflectsARunningServer() async throws {
        try await withServer { client, _ in
            #expect(await client.isReachable())
        }
        let dead = DashboardClient(baseURL: URL(string: "http://127.0.0.1:1")!)
        #expect(await !dead.isReachable())
    }

    @Test func projectCommandsRoundTripThroughTheServer() async throws {
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

    @Test func serverErrorsBecomeTypedServiceErrors() async throws {
        try await withServer { client, home in
            let projects = RemoteProjectCommands(client: client)
            await #expect(throws: ServiceError.self) { try await projects.get(.name("ghost")) }
            do { _ = try await projects.get(.name("ghost")) } catch let error as ServiceError { #expect(error.isNotFound) }

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

    @Test func settingsCommandsRoundTrip() async throws {
        try await withServer { client, _ in
            let settings = RemoteSettingsCommands(client: client)
            #expect(try await settings.current() == .default)
            let updated = try await settings.update(defaultStorage: .sqlite, corsOrigins: ["http://localhost:5173/"])
            #expect(updated == Settings(defaultStorage: .sqlite, corsOrigins: ["http://localhost:5173"]))
            let projects = RemoteProjectCommands(client: client)
            let created = try await projects.add(name: "Follows default", path: NSTemporaryDirectory() + "fd-" + UUID().uuidString, storage: nil)
            #expect(created.storage == .sqlite)
        }
    }

    @Test func unreachableServerIsReportedAsSuch() async {
        let projects = RemoteProjectCommands(client: DashboardClient(baseURL: URL(string: "http://127.0.0.1:1")!, timeout: 1))
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
}
