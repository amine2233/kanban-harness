import Foundation

/// Schema-less JSON, used to round-trip parts of a kanban-rs file this
/// backend does not model (sprints, archives, dependency graph, unknown keys).
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value):
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    /// Rewrites every UUID-shaped string leaf to lowercase, the spelling
    /// kanban-rs (Rust `uuid`) writes; Foundation encodes UUIDs uppercase.
    public func lowercasingUUIDs() -> JSONValue {
        switch self {
        case let .string(value) where value.count == 36 && UUID(uuidString: value) != nil:
            .string(value.lowercased())
        case let .array(values): .array(values.map { $0.lowercasingUUIDs() })
        case let .object(values): .object(values.mapValues { $0.lowercasingUUIDs() })
        default: self
        }
    }

    /// True when any string leaf anywhere inside this value equals `needle` (case-insensitive).
    public func containsString(_ needle: String) -> Bool {
        switch self {
        case let .string(value): value.caseInsensitiveCompare(needle) == .orderedSame
        case let .array(values): values.contains { $0.containsString(needle) }
        case let .object(values): values.values.contains { $0.containsString(needle) }
        default: false
        }
    }
}
