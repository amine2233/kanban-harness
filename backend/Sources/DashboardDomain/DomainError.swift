import Foundation

public enum DomainError: Error, Equatable, Sendable {
    case emptyName
    case nameTooLong(Int)
    case relativePath(String)
    case duplicateName(String)
    case duplicatePath(String)
    case notFound(String)
    case idNotFound(UUID)
    case boardNotFound(UUID)
    case columnNotFound(UUID)
    case cardNotFound(UUID)
    case wipLimitExceeded(column: String, limit: Int)
    case emptyTitle
}

extension DomainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName: "project name must not be empty"
        case let .nameTooLong(max): "project name exceeds \(max) characters"
        case let .relativePath(path): "project path must be absolute: \(path)"
        case let .duplicateName(name): "a project named '\(name)' already exists"
        case let .duplicatePath(path): "a project already uses the path \(path)"
        case let .notFound(name): "project not found: \(name)"
        case let .idNotFound(id): "project id not found: \(id)"
        case let .boardNotFound(id): "board not found: \(id)"
        case let .columnNotFound(id): "column not found: \(id)"
        case let .cardNotFound(id): "card not found: \(id)"
        case let .wipLimitExceeded(column, limit): "column '\(column)' is at its WIP limit of \(limit)"
        case .emptyTitle: "card title must not be empty"
        }
    }
}
