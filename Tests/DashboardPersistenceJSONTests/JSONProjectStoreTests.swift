import DashboardPersistence
import Foundation
import Testing
@testable import DashboardPersistenceJSON

@Suite
struct JSONProjectStoreTests {
    func store() throws -> JSONProjectStore {
        try JSONProjectStore(path: temporaryDirectory() + "/nested/projects.json")
    }

    @Test
    func satisfiesStoreContract() async throws {
        try await StoreContract.verify(store())
    }

    @Test
    func saveCreatesParentDirectoriesAndLeavesNoTempFile() async throws {
        let store = try store()
        try await store.save([StoreContract.sampleProject("A", "a")])
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: store.path + ".tmp"))
    }

    @Test
    func saveWritesVersionedEnvelope() async throws {
        let store = try store()
        try await store.save([StoreContract.sampleProject("A", "a")])
        let raw = try #require(
            JSONSerialization
                .jsonObject(with: Data(contentsOf: URL(fileURLWithPath: store.path))) as? [String: Any]
        )
        #expect(raw["version"] as? Int == registryFormatVersion)
        let projects = try #require(raw["projects"] as? [[String: Any]])
        #expect(projects[0]["name"] as? String == "A")
        #expect(projects[0]["storage"] as? String == "json")
    }

    @Test
    func loadMissingFileReturnsEmpty() async throws {
        #expect(try await store().load().isEmpty)
    }

    @Test
    func loadMalformedJSONThrowsCorrupt() async throws {
        let store = try store()
        try AtomicFile.write(Data("{ not json".utf8), to: store.path)
        await #expect(throws: PersistenceError.self) {
            try await store.load()
        }
    }

    @Test
    func loadFutureVersionThrowsUnsupportedVersion() async throws {
        let store = try store()
        try AtomicFile.write(Data(#"{"version": 99, "projects": []}"#.utf8), to: store.path)
        do {
            _ = try await store.load()
            Issue.record("expected an error")
        } catch let PersistenceError.unsupportedVersion(_, found, supported) {
            #expect(found == 99)
            #expect(supported == registryFormatVersion)
        }
    }
}
