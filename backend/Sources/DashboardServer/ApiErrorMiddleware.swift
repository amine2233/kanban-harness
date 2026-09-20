import DashboardAPI
import DashboardDomain
import DashboardService
import Vapor

/// Maps every failure to the `{code, message}` envelope with a kanban-server style code.
struct ApiErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let requestId = request.requestId.uuidString.lowercased()
        do {
            let response = try await next.respond(to: request)
            response.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
            return response
        } catch {
            let (status, apiError) = Self.classify(error)
            if status == .internalServerError {
                request.logger.report(error: error, metadata: ["request_id": .string(requestId)])
            }
            let response = Response(status: status)
            response.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
            try response.content.encode(apiError, as: .json)
            return response
        }
    }

    static func classify(_ error: any Error) -> (HTTPStatus, ApiError) {
        if let domain = error as? DomainError {
            return classify(ServiceError.domain(domain))
        }
        return switch error {
        case let error as ServiceError where error.isNotFound:
            (.notFound, ApiError(code: "NOT_FOUND", message: error.localizedDescription))
        case let error as ServiceError where error.isConflict:
            (.conflict, ApiError(code: "ALREADY_EXISTS", message: error.localizedDescription))
        case let error as ServiceError where error.isValidation:
            (.badRequest, ApiError(code: "VALIDATION_FAILED", message: error.localizedDescription))
        case let error as DecodingError:
            (.badRequest, ApiError(code: "VALIDATION_FAILED", message: error.reason))
        case let error as any AbortError:
            (error.status, ApiError(code: error.status == .notFound ? "NOT_FOUND" : "VALIDATION_FAILED", message: error.reason))
        default:
            (.internalServerError, ApiError(code: "INTERNAL", message: String(describing: error)))
        }
    }
}

extension DecodingError {
    var reason: String {
        switch self {
        case let .keyNotFound(key, _): "missing field '\(key.stringValue)'"
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            context.debugDescription
        @unknown default: "invalid request body"
        }
    }
}
