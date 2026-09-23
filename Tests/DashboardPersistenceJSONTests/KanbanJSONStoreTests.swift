import DashboardDomain
import DashboardPersistence
import Foundation
import Testing
@testable import DashboardPersistenceJSON

@Suite
struct KanbanJSONStoreTests {
    func store() throws -> KanbanJSONStore {
        try KanbanJSONStore(path: temporaryDirectory() + "/project/kanban.json")
    }

    func storeWithFixture() throws -> KanbanJSONStore {
        let store = try store()
        try AtomicFile.write(fixture("kanban-v18"), to: store.path)
        return store
    }

    func rawJSON(_ store: KanbanJSONStore) throws -> [String: Any] {
        try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: URL(fileURLWithPath: store.path))) as? [String: Any])
    }

    @Test
    func satisfiesStoreContract() async throws {
        try await StoreContract.verify(store())
    }

    @Test
    func loadsFileWrittenByKanbanRs() async throws {
        let workspace = try await storeWithFixture().load()
        #expect(workspace.boards.map(\.name) == ["Sample"])
        #expect(workspace.boards[0].sprintNames == ["S1"])
        #expect(workspace.columns.map(\.name) == ["TODO", "Doing", "Complete"])
        #expect(workspace.columns.map(\.defaultStatus) == [.todo, .inProgress, .done])
        let card = try #require(workspace.cards.first)
        #expect(card.title == "Hello")
        #expect(card.priority == .high)
        #expect(card.status == .todo)
        #expect(card.description == "desc")
        #expect(card.cardNumber == 1)
        #expect(workspace.prefixes.map(\.name) == ["task", "sprint"])
        #expect(workspace.extra["sprints"]?.arrayValue?.count == 1)
        #expect(workspace.extra["graph"]?.objectValue?.keys.sorted() == ["blocks", "relates", "spawns"])
    }

    @Test
    func saveAfterLoadPreservesUnmodelledSectionsAndEnvelope() async throws {
        let store = try storeWithFixture()
        var workspace = try await store.load()
        let column = workspace.columns[1]
        try workspace.createCard(columnId: column.id, title: "From Swift")
        try await store.save(workspace)

        let raw = try rawJSON(store)
        #expect(raw["version"] as? Int == kanbanFormatVersion)
        let metadata = try #require(raw["metadata"] as? [String: Any])
        #expect(metadata["instance_id"] as? String == store.instanceId.uuidString.lowercased())
        #expect(metadata["writer_version"] as? String == KanbanJSONStore.writerVersion)
        let data = try #require(raw["data"] as? [String: Any])
        #expect((data["sprints"] as? [Any])?.count == 1)
        #expect((data["cards"] as? [Any])?.count == 2)
        let prefixes = try #require(data["prefixes"] as? [[String: Any]])
        #expect(prefixes.first { $0["name"] as? String == "task" }?["card_counter"] as? Int == 2)
        let card = try #require((data["cards"] as? [[String: Any]])?.last)
        #expect(
            card["id"] as? String == (card["id"] as? String)?.lowercased(),
            "uuids are written lowercase like kanban-rs"
        )
        #expect(card["status"] as? String == "InProgress")
        #expect(card["priority"] as? String == "Medium")
        #expect(card["sprint_logs"] as? [Any] != nil)
        #expect((card["created_at"] as? String)?.hasSuffix("Z") == true)

        let reloaded = try await store.load()
        #expect(reloaded.cards.count == 2)
        #expect(reloaded.boards == workspace.boards)
    }

    @Test
    func saveOnFreshStoreWritesFullKanbanSkeleton() async throws {
        let store = try store()
        var workspace = Workspace()
        workspace.createBoardWithTemplateColumns(name: "New")
        try await store.save(workspace)
        let data = try #require(try rawJSON(store)["data"] as? [String: Any])
        #expect(Set(data.keys) == [
            "archived_boards",
            "archived_cards",
            "boards",
            "cards",
            "columns",
            "graph",
            "prefixes",
            "sprints"
        ])
    }

    @Test
    func loadRefusesOtherFormatVersions() async throws {
        let store = try store()
        try AtomicFile.write(
            Data(
                #"{"version": 17, "metadata": {"instance_id": "6f1c1c1e-2b0c-4b7c-9d3a-1c2b3c4d5e6f", "saved_at": "2026-01-01T00:00:00Z"}, "data": {}}"#
                    .utf8
            ),
            to: store.path
        )
        do {
            _ = try await store.load()
            Issue.record("expected an error")
        } catch let PersistenceError.unsupportedVersion(_, found, supported) {
            #expect(found == 17)
            #expect(supported == kanbanFormatVersion)
        }
    }

    @Test
    func loadCorruptSectionThrowsCorrupt() async throws {
        let store = try store()
        try AtomicFile.write(
            Data(
                #"{"version": 18, "metadata": {"instance_id": "6f1c1c1e-2b0c-4b7c-9d3a-1c2b3c4d5e6f", "saved_at": "2026-01-01T00:00:00Z"}, "data": {"boards": [{"id": "nope"}]}}"#
                    .utf8
            ),
            to: store.path
        )
        await #expect(throws: PersistenceError.self) {
            try await store.load()
        }
    }
}
