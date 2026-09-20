import DashboardDomain
import Foundation

/// What a board looks like to callers that don't need the full aggregate (CLI listings).
public struct BoardSummary: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let cardPrefix: String?
    public let position: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description, position
        case cardPrefix = "card_prefix"
    }

    public init(id: UUID, name: String, description: String?, cardPrefix: String?, position: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.cardPrefix = cardPrefix
        self.position = position
    }

    public init(_ board: Board) {
        self.init(id: board.id, name: board.name, description: board.description, cardPrefix: board.cardPrefix, position: board.position)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(cardPrefix, forKey: .cardPrefix)
        try container.encode(position, forKey: .position)
    }
}

/// The project operations a front end (CLI, later others) drives. Implemented
/// locally by `ProjectService` and remotely by the HTTP client, so a caller
/// never knows whether it owns the files or talks to the server that does.
public protocol ProjectCommands: Sendable {
    func list() async throws(ServiceError) -> [Project]
    func get(_ reference: ProjectRef) async throws(ServiceError) -> Project
    func add(name: String, path: String, storage: StorageKind?) async throws(ServiceError) -> Project
    func remove(_ reference: ProjectRef) async throws(ServiceError) -> Project
    func changeStorage(_ reference: ProjectRef, to storage: StorageKind) async throws(ServiceError) -> Project
    func boards(_ reference: ProjectRef) async throws(ServiceError) -> [BoardSummary]
}

public protocol SettingsCommands: Sendable {
    func current() async throws(ServiceError) -> Settings
    func update(defaultStorage: StorageKind?, corsOrigins: [String]?) async throws(ServiceError) -> Settings
}

extension SettingsService: SettingsCommands {}

/// Local implementation: owns the files. `storage: nil` falls back to the settings default.
public struct LocalProjectCommands: ProjectCommands {
    private let projects: ProjectService
    private let settings: SettingsService

    public init(projects: ProjectService, settings: SettingsService) {
        self.projects = projects
        self.settings = settings
    }

    public func list() async throws(ServiceError) -> [Project] { try await projects.list() }
    public func get(_ reference: ProjectRef) async throws(ServiceError) -> Project { try await projects.get(reference) }

    public func add(name: String, path: String, storage: StorageKind?) async throws(ServiceError) -> Project {
        let kind: StorageKind
        if let storage {
            kind = storage
        } else {
            kind = try await settings.current().defaultStorage
        }
        return try await projects.add(name: name, path: path, storage: kind)
    }

    public func remove(_ reference: ProjectRef) async throws(ServiceError) -> Project { try await projects.remove(reference) }

    public func changeStorage(_ reference: ProjectRef, to storage: StorageKind) async throws(ServiceError) -> Project {
        try await projects.changeStorage(reference, to: storage)
    }

    public func boards(_ reference: ProjectRef) async throws(ServiceError) -> [BoardSummary] {
        try await projects.workspace(reference).boards.sorted { $0.position < $1.position }.map(BoardSummary.init)
    }
}
