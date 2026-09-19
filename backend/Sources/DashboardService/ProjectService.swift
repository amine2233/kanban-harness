import CascadeKit
import DashboardDomain
import DashboardPersistence
import Foundation

/// Registers project folders and runs commands against their kanban workspaces.
/// An actor so registry and workspace load-mutate-save cycles never interleave.
/// Removing a project only unregisters it; files on disk are never deleted.
public actor ProjectService {
    private let store: any ProjectStore
    private let workspaces: WorkspaceStoreFactory

    @Dependency(\.now) private var now
    @Dependency(\.uuid) private var uuid

    public init(store: any ProjectStore, workspaces: WorkspaceStoreFactory) {
        self.store = store
        self.workspaces = workspaces
    }

    // MARK: Registry

    public func list() async throws(ServiceError) -> [Project] {
        try await registry().projects
    }

    public func get(_ reference: ProjectRef) async throws(ServiceError) -> Project {
        try await wrap { try await registry().get(reference) }
    }

    public func add(name: String, path: String, storage: StorageKind = .json) async throws(ServiceError) -> Project {
        try await wrap {
            let project = try Project(name: name, path: path, storage: storage, id: uuid(), createdAt: now())
            var registry = try await registry()
            try registry.add(project)
            try prepareFolder(project)
            try await seed(project)
            try await store.save(registry.projects)
            return project
        }
    }

    public func remove(_ reference: ProjectRef) async throws(ServiceError) -> Project {
        try await wrap {
            var registry = try await registry()
            let removed = try registry.remove(reference)
            try await store.save(registry.projects)
            return removed
        }
    }

    /// Converts a project's workspace to another format: read through the
    /// current store, write through the new one, then re-point the registry.
    /// The previous file is left on disk as a fallback.
    public func changeStorage(_ reference: ProjectRef, to storage: StorageKind) async throws(ServiceError) -> Project {
        try await wrap {
            var registry = try await registry()
            let project = try registry.get(reference)
            guard project.storage != storage else { return project }
            let workspace = try await workspaces.make(project).load()
            let converted = project.with(storage: storage)
            try await workspaces.make(converted).save(workspace)
            try registry.update(converted)
            try await store.save(registry.projects)
            return converted
        }
    }

    // MARK: Workspaces

    public func workspace(_ reference: ProjectRef) async throws(ServiceError) -> Workspace {
        try await wrap {
            let project = try await registry().get(reference)
            return try await workspaces.make(project).load()
        }
    }

    /// Load → mutate → save under the actor, returning what the mutation produced.
    public func mutate<T: Sendable>(
        _ reference: ProjectRef,
        _ body: @Sendable (inout Workspace, Date) throws -> T
    ) async throws(ServiceError) -> T {
        try await wrap {
            let project = try await registry().get(reference)
            let store = workspaces.make(project)
            var workspace = try await store.load()
            let result = try body(&workspace, now())
            try await store.save(workspace)
            return result
        }
    }

    // MARK: Internals

    private func registry() async throws(ServiceError) -> ProjectRegistry {
        try await wrap { try ProjectRegistry(projects: try await store.load()) }
    }

    private func wrap<T>(_ body: () async throws -> T) async throws(ServiceError) -> T {
        do {
            return try await body()
        } catch {
            throw ServiceError.wrap(error)
        }
    }

    private func prepareFolder(_ project: Project) throws(ServiceError) {
        do {
            try FileManager.default.createDirectory(atPath: project.path, withIntermediateDirectories: true)
        } catch {
            throw .projectFolder(path: project.path, reason: error.localizedDescription)
        }
    }

    /// Seeds a first board (named after the project) with the default template
    /// columns so a fresh project is immediately usable. Existing files are left alone.
    private func seed(_ project: Project) async throws {
        let store = workspaces.make(project)
        var workspace = try await store.load()
        guard workspace.boards.isEmpty else { return }
        workspace.createBoardWithTemplateColumns(name: project.name, now: now())
        try await store.save(workspace)
    }
}
