import DashboardDomain
import DashboardPersistence
import Foundation

public enum ServiceError: Error, Sendable {
    case domain(DomainError)
    case persistence(PersistenceError)
    case projectFolder(path: String, reason: String)
    /// Failure reported by a remote dashboard server (`{code, message}` envelope).
    case remote(code: String, message: String)
    /// The remote server could not be reached at all.
    case unreachable(url: String, reason: String)

    public var isNotFound: Bool {
        switch self {
        case .domain(.notFound), .domain(.idNotFound), .domain(.boardNotFound),
             .domain(.columnNotFound), .domain(.cardNotFound), .domain(.providerNotFound): true
        case let .remote(code, _): code == "NOT_FOUND"
        default: false
        }
    }

    public var isConflict: Bool {
        switch self {
        case .domain(.duplicateName), .domain(.duplicatePath), .domain(.wipLimitExceeded): true
        case let .remote(code, _): code == "ALREADY_EXISTS"
        default: false
        }
    }

    public var isValidation: Bool {
        if case .domain(.invalidOrigin) = self { return true }
        if case .domain = self { return !isNotFound && !isConflict }
        if case let .remote(code, _) = self { return code == "VALIDATION_FAILED" }
        return false
    }

    static func wrap(_ error: any Error) -> ServiceError {
        switch error {
        case let error as ServiceError: error
        case let error as DomainError: .domain(error)
        case let error as PersistenceError: .persistence(error)
        default: .projectFolder(path: "", reason: String(describing: error))
        }
    }
}

extension ServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .domain(error): error.errorDescription
        case let .persistence(error): error.errorDescription
        case let .projectFolder(path, reason): "cannot use project folder \(path): \(reason)"
        case let .remote(_, message): message
        case let .unreachable(url, reason): "dashboard server at \(url) is unreachable: \(reason)"
        }
    }
}
