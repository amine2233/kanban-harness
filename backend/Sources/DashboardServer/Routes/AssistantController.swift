import DashboardAI
import DashboardAPI
import DashboardDomain
import DashboardRuntime
import Vapor

/// `/api/projects/{id}/ai/...`: assistant use cases. Nothing here writes to a
/// board; the client reviews the draft and creates the card itself.
struct AssistantController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("projects", ":project", "ai", "tickets", "draft", use: draft)
    }

    func draft(req: Request) async throws -> DraftTicketResponse {
        let body = try req.content.decode(DraftTicketRequest.self)
        let drafted = try await req.services.make(AssistantCommandsKey.self)
            .draftTicket(project: req.projectRef, boardId: body.boardId, idea: body.idea, providerId: body.provider)
        return DraftTicketResponse(
            draft: drafted.draft, provider: drafted.providerId, model: drafted.model,
            usage: .init(inputTokens: drafted.usage.inputTokens, outputTokens: drafted.usage.outputTokens, costUSD: drafted.usage.costUSD)
        )
    }
}
