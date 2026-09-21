import DashboardDomain
import DashboardService
import Foundation

/// The result of a drafting request: the draft plus which provider produced it.
public struct DraftedTicket: Sendable, Equatable {
    public let draft: TicketDraft
    public let providerId: String
    public let model: String
    public let usage: CompletionUsage

    public init(draft: TicketDraft, providerId: String, model: String, usage: CompletionUsage) {
        self.draft = draft
        self.providerId = providerId
        self.model = model
        self.usage = usage
    }

    /// What to stamp on the card when this draft is turned into one.
    public var aiCost: AICost {
        AICost(provider: providerId, model: model, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, costUSD: usage.costUSD, estimated: usage.estimated)
    }
}

/// A step of the drafting pipeline. Emitted when the step starts and again
/// when it has something to say (`detail`); `elapsedMs` counts from the request.
public struct AssistantStage: Sendable, Equatable {
    public enum Step: String, Sendable, CaseIterable {
        case resolve, context, wait, stream, validate, done
    }

    public let step: Step
    public let detail: String?
    public let elapsedMs: Int

    public init(_ step: Step, detail: String? = nil, elapsedMs: Int) {
        self.step = step
        self.detail = detail
        self.elapsedMs = elapsedMs
    }
}

/// What a client sees while a draft is being produced.
public enum AssistantEvent: Sendable, Equatable {
    case stage(AssistantStage)
    /// Raw model output as it arrives (appended to the previous `text`).
    case text(String)
    case partial(PartialTicketDraft)
    case usage(CompletionUsage)
    case result(DraftedTicket)
}

public protocol AssistantCommands: Sendable {
    /// Streams the drafting of a ticket for `idea` on a board; `providerId` nil = the configured default.
    func streamTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?) -> AsyncThrowingStream<AssistantEvent, any Error>
}

extension AssistantCommands {
    /// The non-streaming form: folds the events into the result.
    public func draftTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?) async throws(ServiceError) -> DraftedTicket {
        do {
            for try await event in streamTicket(project: project, boardId: boardId, idea: idea, providerId: providerId) {
                if case let .result(drafted) = event { return drafted }
            }
            throw ServiceError.remote(code: "AI_PROVIDER", message: "stream ended without a result")
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.remote(code: "AI_PROVIDER", message: String(describing: error))
        }
    }
}

/// Use cases that talk to a model. Providers are resolved from the AI config
/// on every call, so configuration changes apply immediately.
public actor AssistantService: AssistantCommands {
    private let aiConfig: any AIConfigCommands
    private let boards: any BoardCommands
    private let registry: AIProviderRegistry
    private let signIn: (any SignInCommands)?

    public init(aiConfig: any AIConfigCommands, boards: any BoardCommands, registry: AIProviderRegistry, signIn: (any SignInCommands)? = nil) {
        self.aiConfig = aiConfig
        self.boards = boards
        self.registry = registry
        self.signIn = signIn
    }

    public nonisolated func streamTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runTicket(project: project, boardId: boardId, idea: idea, providerId: providerId) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?, emit: @Sendable (AssistantEvent) -> Void) async throws {
        let started = Date()
        func stage(_ step: AssistantStage.Step, _ detail: String?) {
            emit(.stage(AssistantStage(step, detail: detail, elapsedMs: Int(Date().timeIntervalSince(started) * 1000))))
        }
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { throw ServiceError.domain(.emptyTitle) }

        stage(.resolve, nil)
        let (provider, config) = try await resolveProvider(providerId)
        stage(.resolve, "\(config.name) (\(config.model))")

        stage(.context, nil)
        let boardList = try await boards.boards(project)
        guard let board = boardList.first(where: { $0.id == boardId }) else { throw ServiceError.domain(.boardNotFound(boardId)) }
        let columns = try await boards.columns(project, boardId: boardId)
        let cards = try await boards.cards(project, boardId: boardId)
        let request = CompletionRequest(
            system: PromptBuilder.ticketSystemPrompt,
            prompt: PromptBuilder.ticketPrompt(idea: idea, board: board, columns: columns, recentCards: Array(cards.suffix(20))),
            schema: TicketDraft.jsonSchema,
            maxTokens: config.maxTokens ?? 2048
        )
        stage(.context, "\(columns.count) columns, \(min(cards.count, 20)) cards, ~\(request.prompt.count / 4) tokens")

        stage(.wait, nil)
        var usage = CompletionUsage()
        var lastPartial = PartialTicketDraft()
        var first = true
        do {
            for try await event in provider.stream(request) {
                try Task.checkCancellation()
                switch event {
                case let .text(delta):
                    if first { stage(.stream, nil); first = false }
                    emit(.text(delta))
                case let .snapshot(data):
                    if first { stage(.stream, nil); first = false }
                    let partial = PartialTicketDraft.parse(data)
                    if partial != lastPartial, !partial.isEmpty {
                        lastPartial = partial
                        emit(.partial(partial))
                    }
                case let .usage(u):
                    usage = u
                    emit(.usage(u))
                case let .done(json, model):
                    stage(.validate, nil)
                    let draft: TicketDraft
                    do {
                        draft = try TicketDraft.parse(json)
                    } catch {
                        throw ServiceError.remote(code: "AI_BAD_OUTPUT", message: "\(config.name) returned an unusable draft: \(error.localizedDescription)")
                    }
                    let priced = Self.priced(usage, for: config)
                    if priced != usage { emit(.usage(priced)) }
                    stage(.done, nil)
                    emit(.result(DraftedTicket(draft: draft, providerId: config.id, model: model, usage: priced)))
                    return
                }
            }
        } catch let error as ServiceError {
            throw error
        } catch let error as AIProviderError {
            throw ServiceError.remote(code: "AI_PROVIDER", message: error.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError.remote(code: "AI_PROVIDER", message: String(describing: error))
        }
        throw ServiceError.remote(code: "AI_PROVIDER", message: "\(config.name) ended the stream without a result")
    }

    /// Vendor-reported cost wins; otherwise the provider's pricing, or zero for local models.
    static func priced(_ usage: CompletionUsage, for config: AIProviderConfig) -> CompletionUsage {
        guard usage.costUSD == nil else { return usage }
        var priced = usage
        if let pricing = config.pricing {
            priced.costUSD = pricing.cost(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens)
            priced.estimated = true
        } else if config.kind.isFree {
            priced.costUSD = 0
        }
        return priced
    }

    private func resolveProvider(_ id: String?) async throws(ServiceError) -> (any AIProvider, AIProviderConfig) {
        let config = try await aiConfig.current()
        let chosen: AIProviderConfig?
        if let id {
            chosen = config.provider(id)
            guard chosen != nil else { throw .domain(.providerNotFound(id)) }
        } else {
            chosen = config.defaultProvider
            guard chosen != nil else { throw .remote(code: "AI_NOT_CONFIGURED", message: "no AI provider configured — add one in Settings → AI providers") }
        }
        var selected = chosen!
        if let signIn { selected = try await signIn.refreshed(selected) }
        do {
            return (try registry.make(selected), selected)
        } catch {
            throw .remote(code: "AI_PROVIDER", message: (error as? AIProviderError)?.localizedDescription ?? String(describing: error))
        }
    }
}
