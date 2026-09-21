/// Per-namespace counters kanban-rs uses to mint card and sprint numbers.
public struct Prefix: Codable, Hashable, Sendable {
    public let name: String
    public var cardCounter: Int
    public var sprintCounter: Int

    enum CodingKeys: String, CodingKey {
        case name
        case cardCounter = "card_counter"
        case sprintCounter = "sprint_counter"
    }

    public init(name: String, cardCounter: Int = 0, sprintCounter: Int = 0) {
        self.name = name
        self.cardCounter = cardCounter
        self.sprintCounter = sprintCounter
    }

    public static let defaultCardPrefix = "task"
}
