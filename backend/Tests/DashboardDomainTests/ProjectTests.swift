import Foundation
import Testing
@testable import DashboardDomain

@Suite struct ProjectTests {
    @Test func newWithValidInputTrimsName() throws {
        let project = try Project(name: "  Demo  ", path: "/projects/demo")
        #expect(project.name == "Demo")
        #expect(project.path == "/projects/demo")
        #expect(project.storage == .json)
    }

    @Test func newWithBlankNameThrowsEmptyName() {
        #expect(throws: DomainError.emptyName) {
            try Project(name: "   ", path: "/p")
        }
    }

    @Test func newWithTooLongNameThrowsNameTooLong() {
        let name = String(repeating: "x", count: maxProjectNameLength + 1)
        #expect(throws: DomainError.nameTooLong(maxProjectNameLength)) {
            try Project(name: name, path: "/p")
        }
    }

    @Test func newWithRelativePathThrowsRelativePath() {
        #expect(throws: DomainError.relativePath("relative/dir")) {
            try Project(name: "Demo", path: "relative/dir")
        }
    }

    @Test func dataFileJoinsStorageFileName() throws {
        let project = try Project(name: "A", path: "/projects/demo")
        #expect(project.dataFile == "/projects/demo/kanban.json")
    }

    @Test func projectCodableUsesSnakeCaseAndRoundTrips() throws {
        let project = try Project(name: "A", path: "/p", createdAt: Date(timeIntervalSince1970: 0))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["created_at"] as? String == "1970-01-01T00:00:00Z")
        #expect(json["storage"] as? String == "json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Project.self, from: data) == project)
    }

    @Test func projectRefParseDetectsUUIDAndFallsBackToName() {
        let id = UUID()
        #expect(ProjectRef.parse(id.uuidString) == .id(id))
        #expect(ProjectRef.parse("demo") == .name("demo"))
    }

    @Test func projectRefMatchesByIdAndCaseInsensitiveName() throws {
        let project = try Project(name: "Demo", path: "/p")
        #expect(ProjectRef.id(project.id).matches(project))
        #expect(ProjectRef.name("DEMO").matches(project))
        #expect(!ProjectRef.name("Other").matches(project))
        #expect(!ProjectRef.id(UUID()).matches(project))
    }
}
