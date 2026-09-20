import Foundation
import Testing
@testable import DashboardDomain

@Suite struct TicketDraftTests {
    @Test func validatesTrimsAndCapsCriteria() throws {
        let draft = try TicketDraft(title: "  Fix login  ", description: " why ", acceptanceCriteria: [" a ", "", "b"], priority: .high, points: 3)
        #expect(draft.title == "Fix login")
        #expect(draft.description == "why")
        #expect(draft.acceptanceCriteria == ["a", "b"])
        #expect(throws: DomainError.emptyTitle) { try TicketDraft(title: " ") }
        #expect(throws: DomainError.titleTooLong(TicketDraft.maxTitleLength)) { try TicketDraft(title: String(repeating: "x", count: 201)) }
        #expect(throws: DomainError.invalidPoints(999)) { try TicketDraft(title: "t", points: 999) }
        #expect(try TicketDraft(title: "t", description: "  ").description == nil)
    }

    @Test func cardDescriptionRendersCriteriaAsChecklist() throws {
        #expect(try TicketDraft(title: "t").cardDescription == nil)
        let draft = try TicketDraft(title: "t", description: "Why", acceptanceCriteria: ["Works", "Tested"])
        #expect(draft.cardDescription == "Why\n\n**Acceptance criteria**\n- [ ] Works\n- [ ] Tested")
    }

    @Test func parsesProviderJSONWithWireEnumsAndTolerance() throws {
        let draft = try TicketDraft.parse(Data(#"{"title":"Do it","description":null,"acceptance_criteria":["x"],"priority":"critical","points":null}"#.utf8))
        #expect(draft.priority == .critical)
        #expect(draft.description == nil)
        let minimal = try TicketDraft.parse(Data(#"{"title":"Do it"}"#.utf8))
        #expect(minimal.priority == .medium)
        #expect(throws: DomainError.invalidPriority("urgent")) { try TicketDraft.parse(Data(#"{"title":"t","priority":"urgent"}"#.utf8)) }
        #expect(throws: DomainError.emptyTitle) { try TicketDraft.parse(Data(#"{"priority":"low"}"#.utf8)) }
    }

    @Test func codableRoundTripUsesWireTokens() throws {
        let draft = try TicketDraft(title: "t", priority: .high, points: 5)
        let data = try JSONEncoder().encode(draft)
        #expect(String(decoding: data, as: UTF8.self).contains(#""priority":"high""#))
        #expect(try JSONDecoder().decode(TicketDraft.self, from: data) == draft)
        let schema = try JSONEncoder().encode(TicketDraft.jsonSchema)
        #expect(String(decoding: schema, as: UTF8.self).contains(#""enum""#))
    }

    @Test func claudeCodeNeedsNoKey() {
        #expect(!AIProviderKind.claudeCode.requiresAPIKey)
        #expect(AIProviderKind(rawValue: "claude_code") == .claudeCode)
    }
}
