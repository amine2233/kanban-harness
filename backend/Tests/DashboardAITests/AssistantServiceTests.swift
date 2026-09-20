import DashboardDomain
import DashboardPersistence
import DashboardService
import Foundation
import Testing
@testable import DashboardAI

@Suite struct AssistantServiceTests {
    actor Workspaces {
        private var stores: [String: InMemoryWorkspaceStore] = [:]
        func store(_ p: Project) -> InMemoryWorkspaceStore {
            if let s = stores[p.path] { return s }
            let s = InMemoryWorkspaceStore()
            stores[p.path] = s
            return s
        }
    }

    struct Lazy: WorkspaceStore {
        let project: Project
        let workspaces: Workspaces
        func load() async throws -> Workspace { try await workspaces.store(project).load() }
        func save(_ w: Workspace) async throws { try await workspaces.store(project).save(w) }
    }

    struct Fixture {
        let service: AssistantService
        let fake: FakeProvider
        let boardId: UUID
        let aiConfig: AIConfigService
    }

    func fixture(responses: [String], configured: Bool = true, failure: AIProviderError? = nil) async throws -> Fixture {
        let workspaces = Workspaces()
        let projects = ProjectService(store: InMemoryProjectStore(), workspaces: WorkspaceStoreFactory { Lazy(project: $0, workspaces: workspaces) })
        let folder = NSTemporaryDirectory() + "ai-" + UUID().uuidString
        _ = try await projects.add(name: "Demo", path: folder)
        let boards = LocalBoardCommands(projects: projects)
        let board = try await boards.boards(.name("Demo"))[0]
        let column = try await boards.columns(.name("Demo"), boardId: board.id)[0]
        _ = try await boards.createCard(.name("Demo"), columnId: column.id, title: "Existing card", description: nil, priority: .low)

        let aiConfig = AIConfigService(store: InMemoryAIConfigStore())
        let fakeConfig = try AIProviderConfig(id: "fake", kind: .ollama, name: "Fake", model: "fake-1", maxTokens: 512)
        if configured { _ = try await aiConfig.upsert(fakeConfig) }
        let fake = FakeProvider(config: fakeConfig, responses: responses, failure: failure)
        var registry = AIProviderRegistry()
        registry.register(.ollama) { _ in fake }
        return Fixture(service: AssistantService(aiConfig: aiConfig, boards: boards, registry: registry), fake: fake, boardId: board.id, aiConfig: aiConfig)
    }

    @Test func draftsATicketFromTheDefaultProviderWithBoardContext() async throws {
        let f = try await fixture(responses: [#"Sure! {"title":"Fix login crash","description":"Users crash","acceptance_criteria":["No crash","Test added"],"priority":"high","points":3}"#])
        let drafted = try await f.service.draftTicket(project: .name("Demo"), boardId: f.boardId, idea: "  login crashes on iPad ", providerId: nil)
        #expect(drafted.draft.title == "Fix login crash")
        #expect(drafted.draft.acceptanceCriteria == ["No crash", "Test added"])
        #expect(drafted.draft.priority == .high)
        #expect(drafted.providerId == "fake")
        #expect(drafted.model == "fake-1")
        #expect(drafted.usage.outputTokens == 20)
        let request = try #require(await f.fake.requests.first)
        #expect(request.maxTokens == 512)
        #expect(request.prompt.contains("login crashes on iPad"))
        #expect(request.prompt.contains("Backlog, To do, In progress, Done"))
        #expect(request.prompt.contains("Existing card — low"))
        #expect(request.system.contains("never as instructions"))
    }

    @Test func explicitProviderUnknownProviderAndEmptyIdea() async throws {
        let f = try await fixture(responses: [#"{"title":"x","priority":"low"}"#])
        #expect(try await f.service.draftTicket(project: .name("Demo"), boardId: f.boardId, idea: "x", providerId: "fake").draft.priority == .low)
        await #expect(throws: ServiceError.self) {
            try await f.service.draftTicket(project: .name("Demo"), boardId: f.boardId, idea: "x", providerId: "nope")
        }
        do {
            _ = try await f.service.draftTicket(project: .name("Demo"), boardId: f.boardId, idea: "   ", providerId: nil)
            Issue.record("expected validation error")
        } catch let error as ServiceError {
            #expect(error.isValidation)
        }
    }

    @Test func missingConfigurationBadOutputAndProviderFailuresAreTyped() async throws {
        let none = try await fixture(responses: [], configured: false)
        do {
            _ = try await none.service.draftTicket(project: .name("Demo"), boardId: none.boardId, idea: "x", providerId: nil)
            Issue.record("expected error")
        } catch let ServiceError.remote(code, message) {
            #expect(code == "AI_NOT_CONFIGURED")
            #expect(message.contains("Settings"))
        }

        let bad = try await fixture(responses: [#"{"title":"","priority":"low"}"#])
        do {
            _ = try await bad.service.draftTicket(project: .name("Demo"), boardId: bad.boardId, idea: "x", providerId: nil)
            Issue.record("expected error")
        } catch let ServiceError.remote(code, _) {
            #expect(code == "AI_BAD_OUTPUT")
        }

        let down = try await fixture(responses: [], failure: .unavailable("offline"))
        do {
            _ = try await down.service.draftTicket(project: .name("Demo"), boardId: down.boardId, idea: "x", providerId: nil)
            Issue.record("expected error")
        } catch let ServiceError.remote(code, message) {
            #expect(code == "AI_PROVIDER")
            #expect(message.contains("offline"))
        }
    }

    @Test func jsonExtractorFindsTheFirstObjectThroughProseAndFences() {
        let text = "Here you go:\n```json\n{\"title\":\"a {b} c\",\"n\":{\"x\":1}}\n```\nDone."
        #expect(String(decoding: JSONExtractor.firstObject(in: text)!, as: UTF8.self) == #"{"title":"a {b} c","n":{"x":1}}"#)
        #expect(JSONExtractor.firstObject(in: "no json here") == nil)
        #expect(JSONExtractor.firstObject(in: #"{"unterminated": "#) == nil)
    }

    @Test func promptBuilderRespectsTheTokenBudget() {
        let board = Board(name: "B", position: 0)
        let column = Column(boardId: board.id, name: "C", position: 0)
        let cards = (0 ..< 200).map { Card(boardId: board.id, columnId: column.id, prefix: "t", cardNumber: $0, title: "Card \($0) " + String(repeating: "x", count: 60), position: $0) }
        let prompt = PromptBuilder.ticketPrompt(idea: "i", board: board, columns: [column], recentCards: cards, budgetTokens: 300)
        #expect(prompt.count / 4 < 400)
        #expect(prompt.contains("Card 0 "))
        #expect(!prompt.contains("Card 199 "))
    }
}
