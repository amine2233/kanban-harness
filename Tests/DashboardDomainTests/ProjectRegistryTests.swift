import Foundation
import Testing
@testable import DashboardDomain

@Suite struct ProjectRegistryTests {
    private func project(_ name: String, _ dir: String) throws -> Project {
        try Project(name: name, path: "/\(dir)")
    }

    @Test func addDistinctProjectsKeepsInsertionOrder() throws {
        var registry = ProjectRegistry()
        try registry.add(project("A", "a"))
        try registry.add(project("B", "b"))
        #expect(registry.projects.map(\.name) == ["A", "B"])
        #expect(registry.count == 2)
    }

    @Test func addDuplicateNameCaseInsensitiveThrowsDuplicateName() throws {
        var registry = ProjectRegistry()
        try registry.add(project("Demo", "a"))
        #expect(throws: DomainError.duplicateName("Demo")) {
            try registry.add(project("demo", "b"))
        }
        #expect(registry.count == 1)
    }

    @Test func addDuplicatePathThrowsDuplicatePath() throws {
        var registry = ProjectRegistry()
        try registry.add(project("A", "same"))
        #expect(throws: DomainError.duplicatePath("/same")) {
            try registry.add(project("B", "same"))
        }
    }

    @Test func initFromProjectsRejectsInvalidSnapshot() throws {
        let projects = try [project("A", "a"), project("a", "b")]
        #expect(throws: DomainError.duplicateName("A")) {
            try ProjectRegistry(projects: projects)
        }
    }

    @Test func removeByNameReturnsRemovedProject() throws {
        var registry = ProjectRegistry()
        try registry.add(project("A", "a"))
        try registry.add(project("B", "b"))
        let removed = try registry.remove(.name("a"))
        #expect(removed.name == "A")
        #expect(registry.count == 1)
        #expect(registry.find(.name("A")) == nil)
    }

    @Test func removeByIdReturnsRemovedProject() throws {
        var registry = ProjectRegistry()
        let id = try registry.add(project("A", "a")).id
        #expect(try registry.remove(.id(id)).id == id)
        #expect(registry.isEmpty)
    }

    @Test func removeUnknownNameThrowsNotFound() {
        var registry = ProjectRegistry()
        #expect(throws: DomainError.notFound("ghost")) {
            try registry.remove(.name("ghost"))
        }
    }

    @Test func getUnknownIdThrowsIdNotFound() {
        let registry = ProjectRegistry()
        let id = UUID()
        #expect(throws: DomainError.idNotFound(id)) {
            try registry.get(.id(id))
        }
    }

    @Test func updateReplacesProjectWithSameId() throws {
        var registry = ProjectRegistry()
        let project = try registry.add(project("A", "a"))
        try registry.update(project.with(storage: .sqlite))
        #expect(try registry.get(.id(project.id)).storage == .sqlite)
        #expect(registry.count == 1)
    }

    @Test func updateUnknownIdThrowsAndStillChecksInvariants() throws {
        var registry = ProjectRegistry()
        try registry.add(project("A", "a"))
        let b = try registry.add(project("B", "b"))
        let stranger = try project("X", "x")
        #expect(throws: DomainError.idNotFound(stranger.id)) {
            try registry.update(stranger)
        }
        let renamed = try Project(name: "a", path: "/b", id: b.id)
        #expect(throws: DomainError.duplicateName("A")) {
            try registry.update(renamed)
        }
    }

    @Test func projectsRoundTripThroughInit() throws {
        var registry = ProjectRegistry()
        try registry.add(project("A", "a"))
        try registry.add(project("B", "b"))
        #expect(try ProjectRegistry(projects: registry.projects) == registry)
    }
}
