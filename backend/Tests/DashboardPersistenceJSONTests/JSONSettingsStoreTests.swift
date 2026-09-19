import DashboardDomain
import DashboardPersistence
import Foundation
import Testing
@testable import DashboardPersistenceJSON

@Suite struct JSONSettingsStoreTests {
    func store() throws -> JSONSettingsStore {
        try JSONSettingsStore(path: temporaryDirectory() + "/settings.json")
    }

    @Test func satisfiesContract() async throws {
        try await StoreContract.verify(try store())
        try await StoreContract.verify(InMemorySettingsStore())
    }

    @Test func handEditedFileIsPickedUpOnNextLoad() async throws {
        let store = try store()
        try await store.save(.default)
        try AtomicFile.write(Data(#"{"default_storage": "sqlite", "cors_origins": ["HTTP://Localhost:5173/"]}"#.utf8), to: store.path)
        let loaded = try await store.load()
        #expect(loaded.defaultStorage == .sqlite)
        #expect(loaded.corsOrigins == ["http://localhost:5173"])
    }

    @Test func invalidFileSurfacesAsCorrupt() async throws {
        let store = try store()
        try AtomicFile.write(Data(#"{"cors_origins": ["nope"]}"#.utf8), to: store.path)
        await #expect(throws: PersistenceError.self) { try await store.load() }
    }
}
