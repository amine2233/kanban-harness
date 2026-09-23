import DashboardDomain
import Foundation

public struct CreateProjectRequest: Codable, Sendable {
    public var name: String
    public var path: String
    public var storage: StorageKind?

    public init(name: String, path: String, storage: StorageKind? = nil) {
        self.name = name
        self.path = path
        self.storage = storage
    }
}

public struct UpdateProjectRequest: Codable, Sendable {
    public var storage: StorageKind

    public init(storage: StorageKind) {
        self.storage = storage
    }
}

public struct UpdateSettingsRequest: Codable, Sendable {
    public var defaultStorage: StorageKind?
    public var corsOrigins: [String]?

    enum CodingKeys: String, CodingKey {
        case defaultStorage = "default_storage"
        case corsOrigins = "cors_origins"
    }

    public init(defaultStorage: StorageKind? = nil, corsOrigins: [String]? = nil) {
        self.defaultStorage = defaultStorage
        self.corsOrigins = corsOrigins
    }
}

public struct CreateBoardRequest: Codable, Sendable {
    public var name: String
    public var description: String?
    public var cardPrefix: String?
    public var withDefaultColumns: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case cardPrefix = "card_prefix"
        case withDefaultColumns = "with_default_columns"
    }

    public init(
        name: String,
        description: String? = nil,
        cardPrefix: String? = nil,
        withDefaultColumns: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.cardPrefix = cardPrefix
        self.withDefaultColumns = withDefaultColumns
    }
}

public struct UpdateBoardRequest: Codable, Sendable {
    public var name: String?
    public var position: Int?
    public var description: Patch<String> = .keep
    public var cardPrefix: Patch<String> = .keep

    enum CodingKeys: String, CodingKey {
        case name
        case position
        case description
        case cardPrefix = "card_prefix"
    }

    public init(
        name: String? = nil,
        position: Int? = nil,
        description: Patch<String> = .keep,
        cardPrefix: Patch<String> = .keep
    ) {
        self.name = name
        self.position = position
        self.description = description
        self.cardPrefix = cardPrefix
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.position = try container.decodeIfPresent(Int.self, forKey: .position)
        self.description = try container.patch(String.self, forKey: .description)
        self.cardPrefix = try container.patch(String.self, forKey: .cardPrefix)
    }
}

public struct CloneBoardRequest: Codable, Sendable {
    public var name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

public struct CreateColumnRequest: Codable, Sendable {
    public var name: String
    public var wipLimit: Int?
    public var defaultStatus: StatusDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case wipLimit = "wip_limit"
        case defaultStatus = "default_status"
    }

    public init(name: String, wipLimit: Int? = nil, defaultStatus: StatusDTO? = nil) {
        self.name = name
        self.wipLimit = wipLimit
        self.defaultStatus = defaultStatus
    }
}

public struct UpdateColumnRequest: Codable, Sendable {
    public var name: String?
    public var position: Int?
    public var wipLimit: Patch<Int> = .keep
    public var defaultStatus: Patch<StatusDTO> = .keep

    enum CodingKeys: String, CodingKey {
        case name
        case position
        case wipLimit = "wip_limit"
        case defaultStatus = "default_status"
    }

    public init(
        name: String? = nil,
        position: Int? = nil,
        wipLimit: Patch<Int> = .keep,
        defaultStatus: Patch<StatusDTO> = .keep
    ) {
        self.name = name
        self.position = position
        self.wipLimit = wipLimit
        self.defaultStatus = defaultStatus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.position = try container.decodeIfPresent(Int.self, forKey: .position)
        self.wipLimit = try container.patch(Int.self, forKey: .wipLimit)
        self.defaultStatus = try container.patch(StatusDTO.self, forKey: .defaultStatus)
    }
}

extension KeyedDecodingContainer {
    /// Absent key → `.keep`; present (null or value) → decoded `Patch`.
    func patch<T: Codable & Sendable & Equatable>(_: T.Type, forKey key: Key) throws -> Patch<T> {
        contains(key) ? try decode(Patch<T>.self, forKey: key) : .keep
    }
}

public struct CreateCardRequest: Codable, Sendable {
    public var title: String
    public var description: String?
    public var priority: PriorityDTO?
    /// Set by clients that created the card from an AI draft.
    public var aiCost: AICost?
    /// Children created in the same column and linked to the card, atomically.
    public var subtasks: [SubtaskRequest]?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case priority
        case subtasks
        case aiCost = "ai_cost"
    }

    public init(
        title: String,
        description: String? = nil,
        priority: PriorityDTO? = nil,
        aiCost: AICost? = nil,
        subtasks: [SubtaskRequest]? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.aiCost = aiCost
        self.subtasks = subtasks
    }
}

public struct SubtaskRequest: Codable, Sendable, Equatable {
    public var title: String
    public var description: String?
    public var priority: PriorityDTO?
    public var points: Int?

    public init(title: String, description: String? = nil, priority: PriorityDTO? = nil, points: Int? = nil) {
        self.title = title
        self.description = description
        self.priority = priority
        self.points = points
    }

    public init(_ spec: SubtaskSpec) {
        self.init(
            title: spec.title,
            description: spec.description,
            priority: spec.priority.map(PriorityDTO.init),
            points: spec.points
        )
    }

    public func spec() throws -> SubtaskSpec {
        let priority = try priority.map { dto -> CardPriority in
            guard let value = dto.domain else { throw DomainError.invalidPriority(dto.rawValue) }

            return value
        }
        return SubtaskSpec(title: title, description: description, priority: priority, points: points)
    }
}

/// `{"parent_id": uuid}` links the card under a parent; `{"parent_id": null}` detaches it.
public struct SetParentRequest: Codable, Sendable {
    public var parentId: UUID?

    enum CodingKeys: String, CodingKey {
        case parentId = "parent_id"
    }

    public init(parentId: UUID?) {
        self.parentId = parentId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
    }
}

/// Three-state field for PATCH bodies: absent (keep), `null` (clear), value (set).
public enum Patch<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    case keep
    case clear
    case set(T)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .clear : try .set(container.decode(T.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .keep, .clear: try container.encodeNil()
        case let .set(value): try container.encode(value)
        }
    }

    public var value: T?? {
        switch self {
        case .keep: nil
        case .clear: .some(nil)
        case let .set(value): .some(value)
        }
    }
}

public struct UpdateCardRequest: Codable, Sendable {
    public var title: String?
    public var priority: PriorityDTO?
    public var status: StatusDTO?
    public var columnId: UUID?
    /// Move to another board (lands in `column_id` there, or its first column).
    public var boardId: UUID?
    public var description: Patch<String> = .keep
    public var dueDate: Patch<Date> = .keep
    public var points: Patch<Int> = .keep

    enum CodingKeys: String, CodingKey {
        case title
        case priority
        case status
        case description
        case points
        case columnId = "column_id"
        case boardId = "board_id"
        case dueDate = "due_date"
    }

    public init(
        title: String? = nil,
        priority: PriorityDTO? = nil,
        status: StatusDTO? = nil,
        columnId: UUID? = nil,
        boardId: UUID? = nil,
        description: Patch<String> = .keep,
        dueDate: Patch<Date> = .keep,
        points: Patch<Int> = .keep
    ) {
        self.title = title
        self.priority = priority
        self.status = status
        self.columnId = columnId
        self.boardId = boardId
        self.description = description
        self.dueDate = dueDate
        self.points = points
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.priority = try container.decodeIfPresent(PriorityDTO.self, forKey: .priority)
        self.status = try container.decodeIfPresent(StatusDTO.self, forKey: .status)
        self.columnId = try container.decodeIfPresent(UUID.self, forKey: .columnId)
        self.boardId = try container.decodeIfPresent(UUID.self, forKey: .boardId)
        self.description = try container.patch(String.self, forKey: .description)
        self.dueDate = try container.patch(Date.self, forKey: .dueDate)
        self.points = try container.patch(Int.self, forKey: .points)
    }
}
