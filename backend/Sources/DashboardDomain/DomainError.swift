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
    case emptyBoardName
    case emptyColumnName
    case lastColumn(board: String)
    case invalidOrigin(String)
    case invalidProviderId(String)
    case emptyModel(String)
    case invalidMaxTokens(Int)
    case invalidPricing
    case providerNotFound(String)
    case titleTooLong(Int)
    case invalidPoints(Int)
    case invalidPriority(String)
    case selfRelation
    case crossBoardRelation
    case alreadyHasParent(UUID)
    case relationCycle
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
        case .emptyBoardName: "board name must not be empty"
        case .emptyColumnName: "column name must not be empty"
        case let .lastColumn(board): "board '\(board)' must keep at least one column"
        case let .invalidOrigin(origin): "invalid origin '\(origin)': expected http(s)://host[:port]"
        case let .invalidProviderId(id): "invalid provider id '\(id)': use a-z, 0-9 and _, starting with a letter (max 32)"
        case let .emptyModel(id): "provider '\(id)' needs a model"
        case let .invalidMaxTokens(value): "max_tokens must be positive, got \(value)"
        case .invalidPricing: "pricing must be non-negative USD per million tokens"
        case let .providerNotFound(id): "AI provider not found: \(id)"
        case let .titleTooLong(max): "title exceeds \(max) characters"
        case let .invalidPoints(points): "points must be between 0 and 255, got \(points)"
        case let .invalidPriority(raw): "unknown priority '\(raw)'"
        case .selfRelation: "a card cannot be its own parent"
        case .crossBoardRelation: "parent and child must be on the same board"
        case let .alreadyHasParent(id): "card \(id) already has a parent"
        case .relationCycle: "that would make a card its own ancestor"
        }
    }
}
