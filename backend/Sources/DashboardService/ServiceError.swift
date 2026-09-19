import DashboardDomain
import DashboardPersistence
import Foundation

public enum ServiceError: Error, Sendable {
    case domain(DomainError)
    case persistence(PersistenceError)
    case projectFolder(path: String, reason: String)

    public var isNotFound: Bool {
        switch self {
        case .domain(.notFound), .domain(.idNotFound), .domain(.boardNotFound),
             .domain(.columnNotFound), .domain(.cardNotFound): true
        default: false
        }
    }

    public var isConflict: Bool {
        switch self {
        case .domain(.duplicateName), .domain(.duplicatePath), .domain(.wipLimitExceeded): true
        default: false
        }
    }

    public var isValidation: Bool {
        if case .domain = self { return !isNotFound && !isConflict }
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
        }
    }
}
