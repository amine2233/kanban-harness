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
        case name, description
        case cardPrefix = "card_prefix"
        case withDefaultColumns = "with_default_columns"
    }

    public init(name: String, description: String? = nil, cardPrefix: String? = nil, withDefaultColumns: Bool? = nil) {
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
        case name, position, description
        case cardPrefix = "card_prefix"
    }

    public init(name: String? = nil, position: Int? = nil, description: Patch<String> = .keep, cardPrefix: Patch<String> = .keep) {
        self.name = name
        self.position = position
        self.description = description
        self.cardPrefix = cardPrefix
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        description = try container.patch(String.self, forKey: .description)
        cardPrefix = try container.patch(String.self, forKey: .cardPrefix)
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
        case name, position
        case wipLimit = "wip_limit"
        case defaultStatus = "default_status"
    }

    public init(name: String? = nil, position: Int? = nil, wipLimit: Patch<Int> = .keep, defaultStatus: Patch<StatusDTO> = .keep) {
        self.name = name
        self.position = position
        self.wipLimit = wipLimit
        self.defaultStatus = defaultStatus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        wipLimit = try container.patch(Int.self, forKey: .wipLimit)
        defaultStatus = try container.patch(StatusDTO.self, forKey: .defaultStatus)
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

    public init(title: String, description: String? = nil, priority: PriorityDTO? = nil) {
        self.title = title
        self.description = description
        self.priority = priority
    }
}

/// Three-state field for PATCH bodies: absent (keep), `null` (clear), value (set).
public enum Patch<T: Codable & Sendable>: Codable, Sendable, Equatable where T: Equatable {
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
        case title, priority, status, description, points
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
        title = try container.decodeIfPresent(String.self, forKey: .title)
        priority = try container.decodeIfPresent(PriorityDTO.self, forKey: .priority)
        status = try container.decodeIfPresent(StatusDTO.self, forKey: .status)
        columnId = try container.decodeIfPresent(UUID.self, forKey: .columnId)
        boardId = try container.decodeIfPresent(UUID.self, forKey: .boardId)
        description = try container.patch(String.self, forKey: .description)
        dueDate = try container.patch(Date.self, forKey: .dueDate)
        points = try container.patch(Int.self, forKey: .points)
    }
}
