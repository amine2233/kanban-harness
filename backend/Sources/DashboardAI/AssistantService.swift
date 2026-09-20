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
}

public protocol AssistantCommands: Sendable {
    /// Drafts a ticket for `idea` in the context of a board; `providerId` nil = the configured default.
    func draftTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?) async throws(ServiceError) -> DraftedTicket
}

/// Use cases that talk to a model. Providers are resolved from the AI config
/// on every call, so configuration changes apply immediately.
public actor AssistantService: AssistantCommands {
    private let aiConfig: any AIConfigCommands
    private let boards: any BoardCommands
    private let registry: AIProviderRegistry

    public init(aiConfig: any AIConfigCommands, boards: any BoardCommands, registry: AIProviderRegistry) {
        self.aiConfig = aiConfig
        self.boards = boards
        self.registry = registry
    }

    public func draftTicket(project: ProjectRef, boardId: UUID, idea: String, providerId: String?) async throws(ServiceError) -> DraftedTicket {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { throw .domain(.emptyTitle) }
        let (provider, config) = try await resolveProvider(providerId)
        let boardList = try await boards.boards(project)
        guard let board = boardList.first(where: { $0.id == boardId }) else { throw .domain(.boardNotFound(boardId)) }
        let columns = try await boards.columns(project, boardId: boardId)
        let cards = try await boards.cards(project, boardId: boardId)
        let request = CompletionRequest(
            system: PromptBuilder.ticketSystemPrompt,
            prompt: PromptBuilder.ticketPrompt(idea: idea, board: board, columns: columns, recentCards: Array(cards.suffix(20))),
            schema: TicketDraft.jsonSchema,
            maxTokens: config.maxTokens ?? 2048
        )
        let result: CompletionResult
        do {
            result = try await provider.complete(request)
        } catch let error as AIProviderError {
            throw .remote(code: "AI_PROVIDER", message: error.localizedDescription)
        } catch {
            throw .remote(code: "AI_PROVIDER", message: String(describing: error))
        }
        do {
            let draft = try TicketDraft.parse(result.json)
            return DraftedTicket(draft: draft, providerId: config.id, model: result.model, usage: result.usage)
        } catch {
            throw .remote(code: "AI_BAD_OUTPUT", message: "\(config.name) returned an unusable draft: \(error.localizedDescription)")
        }
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
        let selected = chosen!
        do {
            return (try registry.make(selected), selected)
        } catch {
            throw .remote(code: "AI_PROVIDER", message: (error as? AIProviderError)?.localizedDescription ?? String(describing: error))
        }
    }
}
