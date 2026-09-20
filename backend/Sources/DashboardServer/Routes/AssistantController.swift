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

    /// JSON by default; `Accept: text/event-stream` streams `AssistantFrame`s
    /// instead, with failures delivered as an `error` frame on a 200.
    func draft(req: Request) async throws -> Response {
        let body = try req.content.decode(DraftTicketRequest.self)
        let assistant = try req.services.make(AssistantCommandsKey.self)
        guard req.headers.accept.contains(where: { $0.mediaType == eventStream }) else {
            let drafted = try await assistant.draftTicket(project: req.projectRef, boardId: body.boardId, idea: body.idea, providerId: body.provider)
            return try await Self.response(drafted).encodeResponse(for: req)
        }
        let events = try assistant.streamTicket(project: req.projectRef, boardId: body.boardId, idea: body.idea, providerId: body.provider)
        let response = Response(status: .ok)
        response.headers.contentType = eventStream
        response.headers.cacheControl = .init(noCache: true)
        response.body = .init(asyncStream: { writer in
            do {
                for try await event in events {
                    try await writer.write(.buffer(ByteBuffer(data: try Self.frame(event).encoded())))
                }
            } catch {
                let (_, apiError) = ApiErrorMiddleware.classify(error)
                try await writer.write(.buffer(ByteBuffer(data: try AssistantFrame.error(apiError).encoded())))
            }
            try await writer.write(.end)
        })
        return response
    }

    private var eventStream: HTTPMediaType { .init(type: "text", subType: "event-stream", parameters: ["charset": "utf-8"]) }

    private static func frame(_ event: AssistantEvent) -> AssistantFrame {
        switch event {
        case let .stage(name, elapsedMs): .stage(.init(name: name, elapsedMs: elapsedMs))
        case let .partial(partial): .partial(partial)
        case let .usage(usage): .usage(Self.usage(usage))
        case let .result(drafted): .result(response(drafted))
        }
    }

    private static func response(_ drafted: DraftedTicket) -> DraftTicketResponse {
        DraftTicketResponse(draft: drafted.draft, provider: drafted.providerId, model: drafted.model, usage: usage(drafted.usage))
    }

    private static func usage(_ usage: CompletionUsage) -> DraftTicketResponse.UsageDTO {
        .init(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, costUSD: usage.costUSD, estimated: usage.estimated)
    }
}
