import Foundation

/// Aggregate enforcing registry invariants: unique names (case-insensitive) and
/// unique paths. Persistence layers load/save its contents; they never re-implement rules.
public struct ProjectRegistry: Equatable, Sendable {
    public private(set) var projects: [Project]

    public init() {
        projects = []
    }

    public init(projects: [Project]) throws {
        self.init()
        for project in projects {
            try add(project)
        }
    }

    @discardableResult
    public mutating func add(_ project: Project) throws -> Project {
        if let existing = find(.name(project.name)) {
            throw DomainError.duplicateName(existing.name)
        }
        if projects.contains(where: { $0.path == project.path }) {
            throw DomainError.duplicatePath(project.path)
        }
        projects.append(project)
        return project
    }

    @discardableResult
    public mutating func remove(_ reference: ProjectRef) throws -> Project {
        guard let index = projects.firstIndex(where: reference.matches) else {
            throw reference.notFoundError
        }
        return projects.remove(at: index)
    }

    public func find(_ reference: ProjectRef) -> Project? {
        projects.first(where: reference.matches)
    }

    public func get(_ reference: ProjectRef) throws -> Project {
        guard let project = find(reference) else { throw reference.notFoundError }
        return project
    }

    public var isEmpty: Bool { projects.isEmpty }
    public var count: Int { projects.count }
}
