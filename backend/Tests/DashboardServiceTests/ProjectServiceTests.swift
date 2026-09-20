import CascadeKit
import DashboardDomain
import DashboardPersistence
import DashboardPersistenceFluent
import DashboardPersistenceJSON
import Foundation
import Testing
@testable import DashboardService

/// In-memory workspace stores keyed by project path, so a re-added folder keeps its data.
actor MemoryWorkspaces {
    private var stores: [String: InMemoryWorkspaceStore] = [:]

    func store(for project: Project) -> InMemoryWorkspaceStore {
        if let existing = stores[project.path] { return existing }
        let store = InMemoryWorkspaceStore()
        stores[project.path] = store
        return store
    }
}

/// Bridges the sync factory to the actor: blocks briefly on first access per project.
final class LazyWorkspaceStore: WorkspaceStore {
    private let project: Project
    private let workspaces: MemoryWorkspaces

    init(project: Project, workspaces: MemoryWorkspaces) {
        self.project = project
        self.workspaces = workspaces
    }

    func load() async throws -> Workspace { try await workspaces.store(for: project).load() }
    func save(_ workspace: Workspace) async throws { try await workspaces.store(for: project).save(workspace) }
}

func tempDir() throws -> String {
    let path = NSTemporaryDirectory() + "mvp-dashboard-service-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

func memoryService() -> ProjectService {
    let workspaces = MemoryWorkspaces()
    return ProjectService(
        store: InMemoryProjectStore(),
        workspaces: WorkspaceStoreFactory { LazyWorkspaceStore(project: $0, workspaces: workspaces) }
    )
}

func jsonService(home: String) -> ProjectService {
    ProjectService(
        store: JSONProjectStore(path: home + "/projects.json"),
        workspaces: WorkspaceStoreFactory { KanbanJSONStore(path: $0.dataFile) }
    )
}

/// Real files for both formats, chosen per project like the composition roots do.
func fileService(home: String, pool: SQLiteDatabasePool) -> ProjectService {
    ProjectService(
        store: JSONProjectStore(path: home + "/projects.json"),
        workspaces: WorkspaceStoreFactory { project in
            switch project.storage {
            case .json: KanbanJSONStore(path: project.dataFile)
            case .sqlite: SQLiteWorkspaceStore(path: project.dataFile, pool: pool)
            }
        }
    )
}

@Suite struct ProjectServiceTests {
    @Test func addRegistersProjectAndListsIt() async throws {
        let svc = memoryService()
        let project = try await svc.add(name: "Demo", path: try tempDir())
        #expect(try await svc.list() == [project])
    }

    @Test func addUsesInjectedClockAndIds() async throws {
        let fixedDate = Date(timeIntervalSince1970: 42)
        let fixedId = UUID()
        let project = try await withTestDependencies {
            $0.now = { fixedDate }
            $0.uuid = { fixedId }
        } operation: {
            try await memoryService().add(name: "Demo", path: try tempDir())
        }
        #expect(project.id == fixedId)
        #expect(project.createdAt == fixedDate)
    }

    @Test func addCreatesMissingFolderAndSeedsKanbanJSON() async throws {
        let home = try tempDir()
        let folder = home + "/new/project"
        let project = try await jsonService(home: home).add(name: "Demo", path: folder)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: project.dataFile))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: project.dataFile))) as? [String: Any])
        #expect(raw["version"] as? Int == kanbanFormatVersion)
    }

    @Test func addSeedsOneBoardWithTemplateColumns() async throws {
        let svc = memoryService()
        try await svc.add(name: "Demo", path: try tempDir())
        let workspace = try await svc.workspace(.name("demo"))
        #expect(workspace.boards.map(\.name) == ["Demo"])
        #expect(workspace.columns(of: workspace.boards[0].id).map(\.name) == ["Backlog", "To do", "In progress", "Done"])
    }

    @Test func addExistingWorkspaceIsNotReseeded() async throws {
        let svc = memoryService()
        let dir = try tempDir()
        let project = try await svc.add(name: "Demo", path: dir)
        try await svc.remove(.id(project.id))
        let again = try await svc.add(name: "Demo again", path: dir)
        let workspace = try await svc.workspace(.id(again.id))
        #expect(workspace.boards.map(\.name) == ["Demo"])
    }

    @Test func addDuplicateNameIsConflictAndPersistsNothing() async throws {
        let home = try tempDir()
        let svc = jsonService(home: home)
        try await svc.add(name: "Demo", path: try tempDir())
        let other = try tempDir()
        do {
            try await svc.add(name: "demo", path: other)
            Issue.record("expected conflict")
        } catch {
            #expect(error.isConflict)
        }
        #expect(!FileManager.default.fileExists(atPath: other + "/kanban.json"))
        #expect(try await svc.list().count == 1)
    }

    @Test func addRelativePathIsValidationError() async {
        do {
            try await memoryService().add(name: "Demo", path: "relative")
            Issue.record("expected error")
        } catch {
            #expect(error.isValidation)
            guard case .domain(.relativePath("relative")) = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
    }

    @Test func removeUnregistersButKeepsFiles() async throws {
        let home = try tempDir()
        let svc = jsonService(home: home)
        let project = try await svc.add(name: "Demo", path: try tempDir())
        let removed = try await svc.remove(.name("Demo"))
        #expect(removed.id == project.id)
        #expect(try await svc.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: project.dataFile))
    }

    @Test func removeUnknownIsNotFound() async {
        do {
            try await memoryService().remove(.name("ghost"))
            Issue.record("expected error")
        } catch {
            #expect(error.isNotFound)
        }
    }

    @Test func getByIdAndNameReturnSameProject() async throws {
        let svc = memoryService()
        let project = try await svc.add(name: "Demo", path: try tempDir())
        #expect(try await svc.get(.id(project.id)) == project)
        #expect(try await svc.get(.parse("DEMO")) == project)
    }

    @Test func mutatePersistsAndUsesInjectedClock() async throws {
        let fixed = Date(timeIntervalSince1970: 500)
        let svc = memoryService()
        try await svc.add(name: "Demo", path: try tempDir())
        let card = try await withTestDependencies {
            $0.now = { fixed }
        } operation: {
            try await svc.mutate(.name("Demo")) { workspace, now in
                let column = workspace.columns(of: workspace.boards[0].id)[0]
                return try workspace.createCard(columnId: column.id, title: "Persisted", now: now)
            }
        }
        #expect(card.createdAt == fixed)
        let reloaded = try await svc.workspace(.name("Demo"))
        #expect(reloaded.cards.map(\.title) == ["Persisted"])
    }

    @Test func mutateFailureLeavesWorkspaceUntouched() async throws {
        let svc = memoryService()
        try await svc.add(name: "Demo", path: try tempDir())
        do {
            try await svc.mutate(.name("Demo")) { workspace, _ in
                workspace.createBoard(name: "Ghost")
                throw DomainError.emptyTitle
            }
            Issue.record("expected error")
        } catch {
            #expect(error.isValidation)
        }
        #expect(try await svc.workspace(.name("Demo")).boards.count == 1)
    }

    @Test func addWithSQLiteStorageSeedsASQLiteFile() async throws {
        let pool = SQLiteDatabasePool()
        let svc = fileService(home: try tempDir(), pool: pool)
        let project = try await svc.add(name: "Demo", path: try tempDir(), storage: .sqlite)
        #expect(project.dataFile.hasSuffix("kanban.sqlite"))
        let header = try Data(contentsOf: URL(fileURLWithPath: project.dataFile)).prefix(16)
        #expect(String(decoding: header, as: UTF8.self).hasPrefix("SQLite format 3"))
        #expect(try await svc.workspace(.id(project.id)).boards.map(\.name) == ["Demo"])
        await pool.shutdownAll()
    }

    @Test func changeStorageConvertsWorkspaceBothWaysWithoutLoss() async throws {
        let pool = SQLiteDatabasePool()
        let svc = fileService(home: try tempDir(), pool: pool)
        let project = try await svc.add(name: "Demo", path: try tempDir())
        let card = try await svc.mutate(.id(project.id)) { workspace, now in
            let column = workspace.columns(of: workspace.boards[0].id)[1]
            return try workspace.createCard(columnId: column.id, title: "Survives", priority: .critical, now: now)
        }
        let before = try await svc.workspace(.id(project.id))

        let sqlite = try await svc.changeStorage(.id(project.id), to: .sqlite)
        #expect(sqlite.storage == .sqlite)
        #expect(sqlite.id == project.id)
        #expect(try await svc.get(.id(project.id)).storage == .sqlite)
        #expect(FileManager.default.fileExists(atPath: sqlite.dataFile))
        #expect(FileManager.default.fileExists(atPath: project.dataFile), "old json file is kept")
        #expect(try await svc.workspace(.id(project.id)) == before)

        try await svc.mutate(.id(project.id)) { workspace, now in
            try workspace.moveCard(card.id, toColumn: workspace.columns(of: workspace.boards[0].id)[3].id, now: now)
        }
        let json = try await svc.changeStorage(.id(project.id), to: .json)
        #expect(json.storage == .json)
        let after = try await svc.workspace(.id(project.id))
        #expect(after.cards.map(\.title) == ["Survives"])
        #expect(after.cards[0].status == .done)
        #expect(after.prefixes == before.prefixes)
        await pool.shutdownAll()
    }

    @Test func changeStorageToSameKindIsNoOp() async throws {
        let svc = memoryService()
        let project = try await svc.add(name: "Demo", path: try tempDir())
        #expect(try await svc.changeStorage(.id(project.id), to: .json) == project)
    }

    @Test func workspaceForUnknownProjectIsNotFound() async {
        do {
            _ = try await memoryService().workspace(.name("nope"))
            Issue.record("expected error")
        } catch {
            #expect(error.isNotFound)
        }
    }
}
