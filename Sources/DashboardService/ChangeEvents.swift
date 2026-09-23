import Foundation

/// Something the services changed; consumers (WebSocket clients) refetch what it names.
public enum ChangeEvent: Equatable, Sendable {
    /// The project list changed (added, removed, storage switched).
    case projectsChanged
    /// Boards, columns or cards of one project changed.
    case workspaceChanged(projectId: UUID)
    /// settings.json changed.
    case settingsChanged
    /// The AI provider configuration changed.
    case aiConfigChanged
}

/// Fan-out of change events to any number of subscribers (one per WebSocket).
/// Subscribers that fall behind drop the oldest events rather than block publishers.
public actor ChangeBroadcaster {
    private var subscribers: [UUID: AsyncStream<ChangeEvent>.Continuation] = [:]

    public init() {}

    public func publish(_ event: ChangeEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    /// A stream of future events; ends when the consumer stops iterating.
    public func subscribe() -> AsyncStream<ChangeEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ChangeEvent>
            .makeStream(bufferingPolicy: .bufferingNewest(64))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    public var subscriberCount: Int {
        subscribers.count
    }

    private func remove(_ id: UUID) {
        subscribers[id] = nil
    }
}
