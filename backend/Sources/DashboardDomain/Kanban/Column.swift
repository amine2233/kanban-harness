import Foundation

public struct Column: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let boardId: UUID
    public var name: String
    public var position: Int
    public var wipLimit: Int?
    public var defaultStatus: CardStatus?
    public let createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case boardId = "board_id"
        case wipLimit = "wip_limit"
        case defaultStatus = "default_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        boardId: UUID,
        name: String,
        position: Int,
        wipLimit: Int? = nil,
        defaultStatus: CardStatus? = nil,
        id: UUID = UUID(),
        now: Date = Date()
    ) {
        self.id = id
        self.boardId = boardId
        self.name = name
        self.position = position
        self.wipLimit = wipLimit
        self.defaultStatus = defaultStatus
        createdAt = now
        updatedAt = now
    }

    public var isCompletion: Bool { defaultStatus == .done }
}
