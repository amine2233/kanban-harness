import Foundation

/// A parent → child link, kanban-rs' `graph.spawns` edge. Dates are kept as
/// the strings kanban-rs wrote so a file round-trips unchanged; an archived
/// edge is history, not a relation.
public struct SpawnsEdge: Hashable, Sendable {
    public let source: UUID
    public let target: UUID
    public var createdAt: String
    public var archivedAt: String?

    public init(source: UUID, target: UUID, createdAt: String, archivedAt: String? = nil) {
        self.source = source
        self.target = target
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isActive: Bool { archivedAt == nil }

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              case let .string(source)? = object["source"], let sourceId = UUID(uuidString: source),
              case let .string(target)? = object["target"], let targetId = UUID(uuidString: target)
        else { return nil }
        self.source = sourceId
        self.target = targetId
        if case let .string(created)? = object["created_at"] { createdAt = created } else { createdAt = Self.timestamp(Date()) }
        if case let .string(archived)? = object["archived_at"] { archivedAt = archived } else { archivedAt = nil }
    }

    var json: JSONValue {
        .object([
            "source": .string(source.uuidString.lowercased()),
            "target": .string(target.uuidString.lowercased()),
            "created_at": .string(createdAt),
            "archived_at": archivedAt.map(JSONValue.string) ?? .null,
        ])
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// A child card to create under a parent, in one go.
public struct SubtaskSpec: Equatable, Sendable {
    public var title: String
    public var description: String?
    public var priority: CardPriority?
    public var points: Int?

    public init(title: String, description: String? = nil, priority: CardPriority? = nil, points: Int? = nil) {
        self.title = title
        self.description = description
        self.priority = priority
        self.points = points
    }
}

public struct CardProgress: Equatable, Sendable {
    public let total: Int
    public let done: Int

    public init(total: Int, done: Int) {
        self.total = total
        self.done = done
    }
}

extension Workspace {
    // MARK: Queries

    public func parent(of cardId: UUID) -> UUID? {
        spawns.first { $0.isActive && $0.target == cardId }?.source
    }

    /// Direct children, in creation order.
    public func children(of cardId: UUID) -> [Card] {
        let ids = spawns.filter { $0.isActive && $0.source == cardId }.map(\.target)
        return cards.filter { ids.contains($0.id) }.sorted { $0.cardNumber < $1.cardNumber }
    }

    public func progress(of cardId: UUID) -> CardProgress {
        let children = children(of: cardId)
        return CardProgress(total: children.count, done: children.filter { $0.status == .done }.count)
    }

    public func ancestors(of cardId: UUID) -> [UUID] {
        var result: [UUID] = []
        var current = cardId
        while let parent = parent(of: current), !result.contains(parent) {
            result.append(parent)
            current = parent
        }
        return result
    }

    // MARK: Commands

    /// Links `childId` under `parentId`: same board, one parent per card, no cycles.
    @discardableResult
    public mutating func attach(_ childId: UUID, to parentId: UUID, now: Date = .timestamp()) throws -> SpawnsEdge {
        let child = try card(childId)
        let parent = try card(parentId)
        guard childId != parentId else { throw DomainError.selfRelation }
        guard child.boardId == parent.boardId else { throw DomainError.crossBoardRelation }
        if let existing = self.parent(of: childId) {
            guard existing != parentId else { return spawns.first { $0.isActive && $0.target == childId }! }
            throw DomainError.alreadyHasParent(childId)
        }
        guard !ancestors(of: parentId).contains(childId) else { throw DomainError.relationCycle }
        let edge = SpawnsEdge(source: parentId, target: childId, createdAt: SpawnsEdge.timestamp(now))
        spawns.append(edge)
        return edge
    }

    public mutating func detach(_ childId: UUID, now: Date = .timestamp()) throws {
        _ = try card(childId)
        archiveSpawns(now: now) { $0.target == childId }
    }

    /// Creates the children in the parent's column and links them, atomically.
    @discardableResult
    public mutating func createSubtasks(of parentId: UUID, _ specs: [SubtaskSpec], now: Date = .timestamp()) throws -> [Card] {
        let parent = try card(parentId)
        let column = try column(parent.columnId)
        try checkWipLimit(column, adding: specs.count)
        let snapshot = self
        do {
            var created: [Card] = []
            for spec in specs {
                var child = try createCard(columnId: column.id, title: spec.title, description: spec.description, priority: spec.priority ?? parent.priority, now: now)
                if let points = spec.points {
                    child = try updateCard(child.id, points: .some(points), now: now)
                }
                try attach(child.id, to: parentId, now: now)
                created.append(child)
            }
            return created
        } catch {
            self = snapshot
            throw error
        }
    }

    mutating func archiveSpawns(now: Date, where matches: (SpawnsEdge) -> Bool) {
        let stamp = SpawnsEdge.timestamp(now)
        for index in spawns.indices where spawns[index].isActive && matches(spawns[index]) {
            spawns[index].archivedAt = stamp
        }
    }
}
