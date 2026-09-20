import Foundation

/// A proposed card. Produced by an assistant, reviewed by a person, then
/// turned into a real card — never created behind the user's back.
public struct TicketDraft: Codable, Equatable, Sendable {
    public static let maxTitleLength = 200
    public static let maxCriteria = 12

    public var title: String
    public var description: String?
    public var acceptanceCriteria: [String]
    public var priority: CardPriority
    public var points: Int?

    enum CodingKeys: String, CodingKey {
        case title, description, priority, points
        case acceptanceCriteria = "acceptance_criteria"
    }

    public init(title: String, description: String? = nil, acceptanceCriteria: [String] = [], priority: CardPriority = .medium, points: Int? = nil) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw DomainError.emptyTitle }
        guard title.count <= Self.maxTitleLength else { throw DomainError.titleTooLong(Self.maxTitleLength) }
        if let points, !(0 ... 255).contains(points) { throw DomainError.invalidPoints(points) }
        self.title = title
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.acceptanceCriteria = Array(acceptanceCriteria.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(Self.maxCriteria))
        self.priority = priority
        self.points = points
    }

    /// Description plus acceptance criteria as a markdown checklist — what lands on the card.
    public var cardDescription: String? {
        var parts: [String] = []
        if let description { parts.append(description) }
        if !acceptanceCriteria.isEmpty {
            parts.append("**Acceptance criteria**\n" + acceptanceCriteria.map { "- [ ] \($0)" }.joined(separator: "\n"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// JSON Schema every provider is asked to satisfy.
    public static var jsonSchema: JSONValue { .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array(["title", "description", "acceptance_criteria", "priority"].map(JSONValue.string)),
        "properties": .object([
            "title": .object(["type": .string("string"), "description": .string("Short imperative title, max \(maxTitleLength) characters")]),
            "description": .object(["type": .string("string"), "description": .string("What and why, in markdown, 1-3 paragraphs")]),
            "acceptance_criteria": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Verifiable statements, 2-6 items")]),
            "priority": .object(["type": .string("string"), "enum": .array(CardPriority.allCases.map { .string($0.wireValue) })]),
            "points": .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(255), "description": .string("Story points, omit when unsure")]),
        ]),
    ]) }

    /// Decodes a provider's JSON (wire enums, tolerant of nulls) into a validated draft.
    public static func parse(_ data: Data) throws -> TicketDraft {
        let raw = try JSONDecoder().decode(Wire.self, from: data)
        guard let priority = CardPriority(wireValue: raw.priority ?? "medium") else { throw DomainError.invalidPriority(raw.priority ?? "") }
        return try TicketDraft(title: raw.title ?? "", description: raw.description, acceptanceCriteria: raw.acceptance_criteria ?? [], priority: priority, points: raw.points)
    }

    private struct Wire: Decodable {
        var title: String?
        var description: String?
        var acceptance_criteria: [String]?
        var priority: String?
        var points: Int?
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(acceptanceCriteria, forKey: .acceptanceCriteria)
        try c.encode(priority.wireValue, forKey: .priority)
        try c.encode(points, forKey: .points)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .priority)
        guard let priority = CardPriority(wireValue: raw) else { throw DomainError.invalidPriority(raw) }
        try self.init(
            title: c.decode(String.self, forKey: .title),
            description: c.decodeIfPresent(String.self, forKey: .description),
            acceptanceCriteria: c.decodeIfPresent([String].self, forKey: .acceptanceCriteria) ?? [],
            priority: priority,
            points: c.decodeIfPresent(Int.self, forKey: .points)
        )
    }
}
