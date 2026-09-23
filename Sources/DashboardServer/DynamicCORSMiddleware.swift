import DashboardService
import Vapor

/// CORS whose allowed origins come from the live settings file plus any
/// origins passed on the command line, so changes never need a restart.
/// Wraps Vapor's `CORSMiddleware`, rebuilt per request from the current list.
struct DynamicCORSMiddleware: AsyncMiddleware {
    let staticOrigins: [String]

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.headers[.origin].first != nil else {
            return try await next.respond(to: request)
        }

        let origins = await staticOrigins + ((try? request.settings.current().corsOrigins) ?? [])
        guard !origins.isEmpty else {
            return try await next.respond(to: request)
        }

        let cors = CORSMiddleware(configuration: .init(
            allowedOrigin: .any(origins),
            allowedMethods: [.GET, .POST, .PATCH, .DELETE, .OPTIONS],
            allowedHeaders: [.accept, .contentType, .origin]
        ))
        return try await cors.respond(to: request, chainingTo: Bridge(next: next)).get()
    }

    private struct Bridge: Responder {
        let next: any AsyncResponder

        func respond(to request: Request) -> EventLoopFuture<Response> {
            request.eventLoop.makeFutureWithTask { try await next.respond(to: request) }
        }
    }
}
