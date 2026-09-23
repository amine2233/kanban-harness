import Foundation

/// A proposed child card: the model only proposes these when the idea is
/// too big for one card. Priority is inherited from the parent.
public struct SubtaskDraft: Codable, Equatable, Sendable {
    public var title: String
    public var description: String?
    public var points: Int?

    public init(title: String, description: String? = nil, points: Int? = nil) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw DomainError.emptyTitle }
        guard title.count <= TicketDraft.maxTitleLength
        else { throw DomainError.titleTooLong(TicketDraft.maxTitleLength) }

        if let points, !(0 ... 255).contains(points) { throw DomainError.invalidPoints(points) }
        self.title = title
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.points = points
    }

    public var spec: SubtaskSpec {
        SubtaskSpec(title: title, description: description, points: points)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(points, forKey: .points)
    }

    enum CodingKeys: String, CodingKey { case title, description, points }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            title: container.decode(String.self, forKey: .title),
            description: container.decodeIfPresent(String.self, forKey: .description),
            points: container.decodeIfPresent(Int.self, forKey: .points)
        )
    }
}

/// A proposed card. Produced by an assistant, reviewed by a person, then
/// turned into a real card — never created behind the user's back.
public struct TicketDraft: Codable, Equatable, Sendable {
    public static let maxTitleLength = 200
    public static let maxCriteria = 12
    public static let maxSubtasks = 8

    public var title: String
    public var description: String?
    public var acceptanceCriteria: [String]
    public var priority: CardPriority
    public var points: Int?
    public var subtasks: [SubtaskDraft]

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case priority
        case points
        case subtasks
        case acceptanceCriteria = "acceptance_criteria"
    }

    public init(
        title: String,
        description: String? = nil,
        acceptanceCriteria: [String] = [],
        priority: CardPriority = .medium,
        points: Int? = nil,
        subtasks: [SubtaskDraft] = []
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw DomainError.emptyTitle }
        guard title.count <= Self.maxTitleLength else { throw DomainError.titleTooLong(Self.maxTitleLength) }

        if let points, !(0 ... 255).contains(points) { throw DomainError.invalidPoints(points) }
        self.title = title
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self
            .acceptanceCriteria = Array(acceptanceCriteria
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .prefix(Self.maxCriteria))
        self.priority = priority
        self.points = points
        self.subtasks = Array(subtasks.prefix(Self.maxSubtasks))
    }

    /// Description plus acceptance criteria as a markdown checklist — what lands on the card.
    public var cardDescription: String? {
        var parts: [String] = []
        if let description { parts.append(description) }
        if !acceptanceCriteria.isEmpty {
            parts
                .append("**Acceptance criteria**\n" + acceptanceCriteria.map { "- [ ] \($0)" }
                    .joined(separator: "\n"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// JSON Schema every provider is asked to satisfy.
    public static var jsonSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array(["title", "description", "acceptance_criteria", "priority", "subtasks"]
                .map(JSONValue.string)),
            "properties": .object([
                "subtasks": .object([
                    "type": .string("array"), "maxItems": .number(Double(maxSubtasks)),
                    "description": .string(
                        "Child cards, only when the idea clearly needs several independent pieces of work (more than a day, several layers or deliverables); otherwise an empty array. 2-\(maxSubtasks) items, each doable on its own"
                    ),
                    "items": .object([
                        "type": .string("object"), "additionalProperties": .bool(false),
                        "required": .array([.string("title")]),
                        "properties": .object([
                            "title": .object([
                                "type": .string("string"),
                                "description": .string("Short imperative title")
                            ]),
                            "description": .object([
                                "type": .string("string"),
                                "description": .string("One or two sentences: what exactly to do")
                            ]),
                            "points": .object([
                                "type": .string("integer"),
                                "minimum": .number(0),
                                "maximum": .number(255),
                                "description": .string("Story points, omit when unsure")
                            ])
                        ])
                    ])
                ]),
                "title": .object([
                    "type": .string("string"),
                    "description": .string("Short imperative title, max \(maxTitleLength) characters")
                ]),
                "description": .object([
                    "type": .string("string"),
                    "description": .string("What and why, in markdown, 1-3 paragraphs")
                ]),
                "acceptance_criteria": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Verifiable statements, 2-6 items")
                ]),
                "priority": .object([
                    "type": .string("string"),
                    "enum": .array(CardPriority.allCases.map { .string($0.wireValue) })
                ]),
                "points": .object([
                    "type": .string("integer"),
                    "minimum": .number(0),
                    "maximum": .number(255),
                    "description": .string("Story points, omit when unsure")
                ])
            ])
        ])
    }

    /// Decodes a provider's JSON (wire enums, tolerant of nulls) into a validated draft.
    public static func parse(_ data: Data) throws -> TicketDraft {
        let raw = try JSONDecoder().decode(Wire.self, from: data)
        guard let priority = CardPriority(wireValue: raw.priority ?? "medium")
        else { throw DomainError.invalidPriority(raw.priority ?? "") }

        let subtasks = try (raw.subtasks ?? []).map { try SubtaskDraft(
            title: $0.title ?? "",
            description: $0.description,
            points: $0.points
        ) }
        return try TicketDraft(
            title: raw.title ?? "",
            description: raw.description,
            acceptanceCriteria: raw.acceptance_criteria ?? [],
            priority: priority,
            points: raw.points,
            subtasks: subtasks
        )
    }

    private struct Wire: Decodable {
        var title: String?
        var description: String?
        var acceptance_criteria: [String]?
        var priority: String?
        var points: Int?
        var subtasks: [WireSubtask]?
    }

    private struct WireSubtask: Decodable {
        var title: String?
        var description: String?
        var points: Int?
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(acceptanceCriteria, forKey: .acceptanceCriteria)
        try container.encode(priority.wireValue, forKey: .priority)
        try container.encode(points, forKey: .points)
        try container.encode(subtasks, forKey: .subtasks)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .priority)
        guard let priority = CardPriority(wireValue: raw) else { throw DomainError.invalidPriority(raw) }

        try self.init(
            title: container.decode(String.self, forKey: .title),
            description: container.decodeIfPresent(String.self, forKey: .description),
            acceptanceCriteria: container.decodeIfPresent([String].self, forKey: .acceptanceCriteria) ?? [],
            priority: priority,
            points: container.decodeIfPresent(Int.self, forKey: .points),
            subtasks: container.decodeIfPresent([SubtaskDraft].self, forKey: .subtasks) ?? []
        )
    }
}

/// A draft while the model is still writing it: every field optional, criteria
/// only complete items. Decoded from best-effort-completed JSON, never fails on shape.
public struct PartialTicketDraft: Codable, Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var acceptanceCriteria: [String]
    public var priority: CardPriority?
    public var points: Int?
    /// Sub-tasks with at least a title so far.
    public var subtasks: [PartialSubtask]

    public struct PartialSubtask: Codable, Equatable, Sendable {
        public var title: String
        public var description: String?
        public var points: Int?

        public init(title: String, description: String? = nil, points: Int? = nil) {
            self.title = title
            self.description = description
            self.points = points
        }
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case priority
        case points
        case subtasks
        case acceptanceCriteria = "acceptance_criteria"
    }

    public init(
        title: String? = nil,
        description: String? = nil,
        acceptanceCriteria: [String] = [],
        priority: CardPriority? = nil,
        points: Int? = nil,
        subtasks: [PartialSubtask] = []
    ) {
        self.title = title
        self.description = description
        self.acceptanceCriteria = acceptanceCriteria
        self.priority = priority
        self.points = points
        self.subtasks = subtasks
    }

    public static func parse(_ data: Data) -> PartialTicketDraft {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return PartialTicketDraft() }

        let subtasks = (object["subtasks"] as? [Any])?.compactMap { item -> PartialSubtask? in
            guard let fields = item as? [String: Any], let title = fields["title"] as? String,
                  !title.isEmpty else { return nil }

            return PartialSubtask(
                title: title,
                description: fields["description"] as? String,
                points: fields["points"] as? Int
            )
        } ?? []
        return PartialTicketDraft(
            title: object["title"] as? String,
            description: object["description"] as? String,
            acceptanceCriteria: (object["acceptance_criteria"] as? [Any])?.compactMap { $0 as? String } ?? [],
            priority: (object["priority"] as? String).flatMap(CardPriority.init(wireValue:)),
            points: object["points"] as? Int,
            subtasks: subtasks
        )
    }

    public var isEmpty: Bool {
        title == nil && description == nil && acceptanceCriteria
            .isEmpty && priority == nil && points == nil && subtasks.isEmpty
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.acceptanceCriteria = try container
            .decodeIfPresent([String].self, forKey: .acceptanceCriteria) ?? []
        self.priority = try container.decodeIfPresent(String.self, forKey: .priority)
            .flatMap(CardPriority.init(wireValue:))
        self.points = try container.decodeIfPresent(Int.self, forKey: .points)
        self.subtasks = try container.decodeIfPresent([PartialSubtask].self, forKey: .subtasks) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(acceptanceCriteria, forKey: .acceptanceCriteria)
        try container.encode(priority?.wireValue, forKey: .priority)
        try container.encode(points, forKey: .points)
        try container.encode(subtasks, forKey: .subtasks)
    }
}
