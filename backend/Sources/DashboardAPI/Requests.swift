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
    public var description: Patch<String> = .keep

    enum CodingKeys: String, CodingKey {
        case title, priority, status, description
        case columnId = "column_id"
    }

    public init(
        title: String? = nil,
        priority: PriorityDTO? = nil,
        status: StatusDTO? = nil,
        columnId: UUID? = nil,
        description: Patch<String> = .keep
    ) {
        self.title = title
        self.priority = priority
        self.status = status
        self.columnId = columnId
        self.description = description
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        priority = try container.decodeIfPresent(PriorityDTO.self, forKey: .priority)
        status = try container.decodeIfPresent(StatusDTO.self, forKey: .status)
        columnId = try container.decodeIfPresent(UUID.self, forKey: .columnId)
        description = container.contains(.description)
            ? try container.decode(Patch<String>.self, forKey: .description)
            : .keep
    }
}
