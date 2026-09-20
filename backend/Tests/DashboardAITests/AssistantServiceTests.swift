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
        _ = try await boards.createCard(.name("Demo"), columnId: column.id, title: "Existing card", description: nil, priority: .low, aiCost: nil)

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

    @Test func draftCostComesFromTheVendorThenPricingThenFree() throws {
        let reported = CompletionUsage(inputTokens: 10, outputTokens: 20, costUSD: 0.5)
        let tokensOnly = CompletionUsage(inputTokens: 1_000_000, outputTokens: 100_000)
        let priced = try AIProviderConfig(id: "a", kind: .anthropic, name: "A", model: "m", pricing: AIPricing(inputPerMillion: 3, outputPerMillion: 15))
        let unpriced = try AIProviderConfig(id: "a", kind: .anthropic, name: "A", model: "m")
        let local = try AIProviderConfig(id: "l", kind: .ollama, name: "L", model: "m")
        #expect(AssistantService.priced(reported, for: priced) == reported, "a reported cost is never overridden")
        #expect(AssistantService.priced(tokensOnly, for: priced) == CompletionUsage(inputTokens: 1_000_000, outputTokens: 100_000, costUSD: 4.5, estimated: true))
        #expect(AssistantService.priced(tokensOnly, for: unpriced).costUSD == nil, "no pricing, no guess")
        #expect(AssistantService.priced(tokensOnly, for: local) == CompletionUsage(inputTokens: 1_000_000, outputTokens: 100_000, costUSD: 0))
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

@Suite struct AssistantStreamingTests {
    @Test func streamsStagesPartialsUsageThenTheResult() async throws {
        let f = try await AssistantServiceTests().fixture(responses: [#"{"title":"Fix login crash","description":"Users crash","acceptance_criteria":["No crash"],"priority":"high"}"#])
        var stages: [String] = []
        var partials: [PartialTicketDraft] = []
        var usage: CompletionUsage?
        var result: DraftedTicket?
        for try await event in f.service.streamTicket(project: .name("Demo"), boardId: f.boardId, idea: "login crashes", providerId: nil) {
            switch event {
            case let .stage(name, elapsedMs):
                #expect(elapsedMs >= 0)
                stages.append(name)
            case let .partial(p): partials.append(p)
            case let .usage(u): usage = u
            case let .result(r): result = r
            }
        }
        #expect(stages.first == "resolving provider")
        #expect(stages.contains("provider Fake (fake-1)"))
        #expect(stages.contains { $0.hasPrefix("context: 4 columns, 1 cards") })
        #expect(stages.suffix(3) == ["streaming", "validating", "done"])
        #expect(partials.count > 1, "chunks of 12 characters produce several distinct partials")
        #expect(partials.first?.title?.isEmpty == false)
        #expect(partials.last?.title == "Fix login crash")
        #expect(partials.last?.acceptanceCriteria == ["No crash"])
        #expect(partials == partials.reduce(into: []) { if $0.last != $1 { $0.append($1) } }, "no duplicate partials")
        #expect(usage == CompletionUsage(inputTokens: 10, outputTokens: 20, costUSD: 0), "a local provider is free")
        #expect(result?.draft.title == "Fix login crash")
        #expect(result?.usage == usage)
    }

    @Test func failuresEndTheStreamWithATypedError() async throws {
        let f = try await AssistantServiceTests().fixture(responses: [], failure: .unavailable("offline"))
        var sawResult = false
        do {
            for try await event in f.service.streamTicket(project: .name("Demo"), boardId: f.boardId, idea: "x", providerId: nil) {
                if case .result = event { sawResult = true }
            }
            Issue.record("expected error")
        } catch let ServiceError.remote(code, message) {
            #expect(code == "AI_PROVIDER")
            #expect(message.contains("offline"))
        }
        #expect(!sawResult)
    }
}
