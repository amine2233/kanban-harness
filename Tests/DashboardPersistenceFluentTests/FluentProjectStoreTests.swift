import DashboardDomain
import DashboardPersistence
import Foundation
import Testing
@testable import DashboardPersistenceFluent

@Suite(.serialized)
struct FluentProjectStoreTests {
    func registry() async throws -> SQLiteDatabase {
        let path = NSTemporaryDirectory() + "mvp-dashboard-fluent-" + UUID().uuidString + "/nested/projects.sqlite"
        let registry = try SQLiteDatabase.registry(path: path)
        try await registry.migrate()
        return registry
    }

    @Test
    func satisfiesStoreContract() async throws {
        let registry = try await registry()
        try await StoreContract.verify(FluentProjectStore(database: registry.database))
        try await registry.shutdown()
    }

    @Test
    func migrateCreatesParentDirectoriesAndIsIdempotent() async throws {
        let registry = try await registry()
        try await registry.migrate()
        #expect(FileManager.default.fileExists(atPath: registry.path))
        try await registry.shutdown()
    }

    @Test
    func dataSurvivesReopeningTheFile() async throws {
        let first = try await registry()
        let project = StoreContract.sampleProject("Persist", "p")
        try await FluentProjectStore(database: first.database).save([project])
        try await first.shutdown()

        let second = try SQLiteDatabase.registry(path: first.path)
        try await second.migrate()
        #expect(try await FluentProjectStore(database: second.database).load() == [project])
        try await second.shutdown()
    }

    @Test
    func loadRejectsUnknownStorageValue() async throws {
        let registry = try await registry()
        let model = ProjectModel(StoreContract.sampleProject("Bad", "b"))
        model.storage = "yaml"
        try await model.create(on: registry.database)
        await #expect(throws: (any Error).self) {
            try await FluentProjectStore(database: registry.database).load()
        }
        try await registry.shutdown()
    }
}
