import Foundation

public let maxProjectNameLength = 64

/// Which store format lives inside the project folder. Both hold the same
/// `Workspace` aggregate and can be switched at any time.
public enum StorageKind: String, Codable, Sendable, CaseIterable {
    case json
    case sqlite

    public var fileName: String {
        switch self {
        case .json: "kanban.json"
        case .sqlite: "kanban.sqlite"
        }
    }
}

/// A registered project: a folder on this machine holding a kanban-rs workspace file.
public struct Project: Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    public private(set) var storage: StorageKind
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, path, storage
        case createdAt = "created_at"
    }

    public init(
        name: String,
        path: String,
        storage: StorageKind = .json,
        id: UUID = UUID(),
        createdAt: Date = .timestamp()
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyName }
        guard trimmed.count <= maxProjectNameLength else {
            throw DomainError.nameTooLong(maxProjectNameLength)
        }
        guard path.hasPrefix("/") else { throw DomainError.relativePath(path) }
        self.id = id
        self.name = trimmed
        self.path = path
        self.storage = storage
        self.createdAt = createdAt
    }

    public var dataFile: String {
        (path as NSString).appendingPathComponent(storage.fileName)
    }

    public func with(storage: StorageKind) -> Project {
        var copy = self
        copy.storage = storage
        return copy
    }
}

/// How callers address a project: by id or by name, the way kanban-rs accepts UUIDs or names.
public enum ProjectRef: Equatable, Sendable, CustomStringConvertible {
    case id(UUID)
    case name(String)

    public static func parse(_ input: String) -> ProjectRef {
        if let id = UUID(uuidString: input) { return .id(id) }
        return .name(input)
    }

    public func matches(_ project: Project) -> Bool {
        switch self {
        case let .id(id): project.id == id
        case let .name(name): project.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    public var description: String {
        switch self {
        case let .id(id): id.uuidString
        case let .name(name): name
        }
    }

    var notFoundError: DomainError {
        switch self {
        case let .id(id): .idNotFound(id)
        case let .name(name): .notFound(name)
        }
    }
}
