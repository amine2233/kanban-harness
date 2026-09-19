import Foundation

/// A kanban-rs board record (persisted schema version 18). Sprint bookkeeping
/// fields are carried untouched so the `kanban` CLI/TUI keeps working on the file.
public struct Board: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var cardPrefix: String?
    public var sprintPrefix: String?
    public var taskListView: String
    public var taskSortField: String
    public var taskSortOrder: String
    public var sprintDurationDays: Int?
    public var activeSprintId: UUID?
    public var position: Int
    public var nextSprintNumber: Int
    public var sprintNameUsedCount: Int
    public var sprintNames: [String]
    public let createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, position
        case cardPrefix = "card_prefix"
        case sprintPrefix = "sprint_prefix"
        case taskListView = "task_list_view"
        case taskSortField = "task_sort_field"
        case taskSortOrder = "task_sort_order"
        case sprintDurationDays = "sprint_duration_days"
        case activeSprintId = "active_sprint_id"
        case nextSprintNumber = "next_sprint_number"
        case sprintNameUsedCount = "sprint_name_used_count"
        case sprintNames = "sprint_names"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(name: String, position: Int, id: UUID = UUID(), now: Date = Date()) {
        self.id = id
        self.name = name
        description = nil
        cardPrefix = nil
        sprintPrefix = nil
        taskListView = "Flat"
        taskSortField = "Default"
        taskSortOrder = "Ascending"
        sprintDurationDays = nil
        activeSprintId = nil
        self.position = position
        nextSprintNumber = 1
        sprintNameUsedCount = 0
        sprintNames = []
        createdAt = now
        updatedAt = now
    }
}
