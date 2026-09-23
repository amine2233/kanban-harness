import DashboardDomain
import DashboardPersistence
import DashboardService
import Foundation
import Testing
@testable import DashboardAI

@Suite
struct AssistantServiceTests {
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
        func load() async throws -> Workspace {
            try await workspaces.store(project).load()
        }

        func save(_ w: Workspace) async throws {
            try await workspaces.store(project).save(w)
        }
    }

    struct Fixture {
        let service: AssistantService
        let fake: FakeProvider
        let boardId: UUID
        let aiConfig: AIConfigService
    }

    func fixture(
        responses: [String],
        configured: Bool = true,
        failure: AIProviderError? = nil
    ) async throws -> Fixture {
        let workspaces = Workspaces()
        let projects = ProjectService(
            store: InMemoryProjectStore(),
            workspaces: WorkspaceStoreFactory { Lazy(project: $0, workspaces: workspaces) }
        )
        let folder = NSTemporaryDirectory() + "ai-" + UUID().uuidString
        _ = try await projects.add(name: "Demo", path: folder)
        let boards = LocalBoardCommands(projects: projects)
        let board = try await boards.boards(.name("Demo"))[0]
        let column = try await boards.columns(.name("Demo"), boardId: board.id)[0]
        _ = try await boards.createCard(
            .name("Demo"),
            columnId: column.id,
            title: "Existing card",
            description: nil,
            priority: .low,
            aiCost: nil,
            subtasks: []
        )

        let aiConfig = AIConfigService(store: InMemoryAIConfigStore())
        let fakeConfig = try AIProviderConfig(
            id: "fake",
            kind: .ollama,
            name: "Fake",
            model: "fake-1",
            maxTokens: 512
        )
        if configured { _ = try await aiConfig.upsert(fakeConfig) }
        let fake = FakeProvider(config: fakeConfig, responses: responses, failure: failure)
        var registry = AIProviderRegistry()
        registry.register(.ollama) { _ in fake }
        return Fixture(
            service: AssistantService(aiConfig: aiConfig, boards: boards, registry: registry),
            fake: fake,
            boardId: board.id,
            aiConfig: aiConfig
        )
    }

    @Test
    func draftsATicketFromTheDefaultProviderWithBoardContext() async throws {
        let f =
            try await fixture(
                responses: [
                    #"Sure! {"title":"Fix login crash","description":"Users crash","acceptance_criteria":["No crash","Test added"],"priority":"high","points":3}"#
                ]
            )
        let drafted = try await f.service.draftTicket(
            project: .name("Demo"),
            boardId: f.boardId,
            idea: "  login crashes on iPad ",
            providerId: nil
        )
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

    @Test
    func explicitProviderUnknownProviderAndEmptyIdea() async throws {
        let f = try await fixture(responses: [#"{"title":"x","priority":"low"}"#])
        #expect(try await f.service.draftTicket(
            project: .name("Demo"),
            boardId: f.boardId,
            idea: "x",
            providerId: "fake"
        ).draft.priority == .low)
        await #expect(throws: ServiceError.self) {
            try await f.service.draftTicket(
                project: .name("Demo"),
                boardId: f.boardId,
                idea: "x",
                providerId: "nope"
            )
        }
        do {
            _ = try await f.service.draftTicket(
                project: .name("Demo"),
                boardId: f.boardId,
                idea: "   ",
                providerId: nil
            )
            Issue.record("expected validation error")
        } catch let error as ServiceError {
            #expect(error.isValidation)
        }
    }

    /// The remote error a draft ends with, or nil when it succeeded.
    /// (A plain value instead of `catch let ServiceError.remote(...)`: that pattern crashes the Linux 6.3.3
    /// compiler.)
    func remoteFailure(_ f: Fixture) async -> (code: String, message: String)? {
        var failure: ServiceError?
        do {
            _ = try await f.service.draftTicket(
                project: .name("Demo"),
                boardId: f.boardId,
                idea: "x",
                providerId: nil
            )
        } catch {
            failure = error
        }
        guard case let .remote(code, message)? = failure else { return nil }

        return (code, message)
    }

    @Test
    func missingConfigurationBadOutputAndProviderFailuresAreTyped() async throws {
        let none = try await remoteFailure(fixture(responses: [], configured: false))
        #expect(none?.code == "AI_NOT_CONFIGURED")
        #expect(none?.message.contains("Settings") == true)

        let bad = try await remoteFailure(fixture(responses: [#"{"title":"","priority":"low"}"#]))
        #expect(bad?.code == "AI_BAD_OUTPUT")

        let down = try await remoteFailure(fixture(responses: [], failure: .unavailable("offline")))
        #expect(down?.code == "AI_PROVIDER")
        #expect(down?.message.contains("offline") == true)
    }

    @Test
    func jsonExtractorFindsTheFirstObjectThroughProseAndFences() throws {
        let text = "Here you go:\n```json\n{\"title\":\"a {b} c\",\"n\":{\"x\":1}}\n```\nDone."
        #expect(try String(decoding: #require(JSONExtractor.firstObject(in: text)), as: UTF8.self) ==
            #"{"title":"a {b} c","n":{"x":1}}"#)
        #expect(JSONExtractor.firstObject(in: "no json here") == nil)
        #expect(JSONExtractor.firstObject(in: #"{"unterminated": "#) == nil)
    }

    @Test
    func promptBuilderRespectsTheTokenBudget() {
        let board = Board(name: "B", position: 0)
        let column = Column(boardId: board.id, name: "C", position: 0)
        let cards = (0 ..< 200).map { Card(
            boardId: board.id,
            columnId: column.id,
            prefix: "t",
            cardNumber: $0,
            title: "Card \($0) " + String(repeating: "x", count: 60),
            position: $0
        ) }
        let prompt = PromptBuilder.ticketPrompt(
            idea: "i",
            board: board,
            columns: [column],
            recentCards: cards,
            budgetTokens: 300
        )
        #expect(prompt.count / 4 < 400)
        #expect(prompt.contains("Card 0 "))
        #expect(!prompt.contains("Card 199 "))
    }
}

@Suite
struct AssistantStreamingTests {
    @Test
    func streamsStagesPartialsUsageThenTheResult() async throws {
        let f = try await AssistantServiceTests()
            .fixture(
                responses: [
                    #"{"title":"Fix login crash","description":"Users crash","acceptance_criteria":["No crash"],"priority":"high"}"#
                ]
            )
        var stages: [AssistantStage] = []
        var partials: [PartialTicketDraft] = []
        var text = ""
        var usage: CompletionUsage?
        var result: DraftedTicket?
        for try await event in f.service.streamTicket(
            project: .name("Demo"),
            boardId: f.boardId,
            idea: "login crashes",
            providerId: nil
        ) {
            switch event {
            case let .stage(stage):
                #expect(stage.elapsedMs >= 0)
                stages.append(stage)
            case let .text(delta): text += delta
            case let .partial(p): partials.append(p)
            case let .usage(u): usage = u
            case let .result(r): result = r
            }
        }
        #expect(stages.map(\.step) == [
            .resolve,
            .resolve,
            .context,
            .context,
            .wait,
            .stream,
            .validate,
            .done
        ])
        #expect(stages[1].detail == "Fake (fake-1)")
        #expect(stages[3].detail?.hasPrefix("4 columns, 1 cards") == true)
        #expect(stages.allSatisfy { $0.step == .resolve || $0.step == .context || $0.detail == nil })
        #expect(text.hasPrefix(#"{"title":"Fix login crash""#), "raw model output is relayed verbatim")
        #expect(partials.count > 1, "chunks of 12 characters produce several distinct partials")
        #expect(partials.first?.title?.isEmpty == false)
        #expect(partials.last?.title == "Fix login crash")
        #expect(partials.last?.acceptanceCriteria == ["No crash"])
        #expect(
            partials == partials.reduce(into: []) { if $0.last != $1 { $0.append($1) } },
            "no duplicate partials"
        )
        #expect(
            usage == CompletionUsage(inputTokens: 10, outputTokens: 20, costUSD: 0),
            "a local provider is free"
        )
        #expect(result?.draft.title == "Fix login crash")
        #expect(result?.usage == usage)
    }

    @Test
    func failuresEndTheStreamWithATypedError() async throws {
        let f = try await AssistantServiceTests().fixture(responses: [], failure: .unavailable("offline"))
        var sawResult = false
        var failure: (any Error)?
        do {
            for try await event in f.service.streamTicket(
                project: .name("Demo"),
                boardId: f.boardId,
                idea: "x",
                providerId: nil
            ) {
                if case .result = event { sawResult = true }
            }
        } catch {
            failure = error
        }
        guard case let .remote(code, message)? = failure as? ServiceError
        else { Issue.record("expected a remote error, got \(String(describing: failure))"); return }

        #expect(code == "AI_PROVIDER")
        #expect(message.contains("offline"))
        #expect(!sawResult)
    }
}
