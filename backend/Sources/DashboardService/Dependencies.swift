import CascadeKit
import Foundation

/// Cross-cutting values resolved through cascade-kit so tests can pin time and ids.
public enum NowKey: DependencyKey {
    public static let liveValue: @Sendable () -> Date = { Date() }
}

public enum UUIDKey: DependencyKey {
    public static let liveValue: @Sendable () -> UUID = { UUID() }
}

extension DependencyValues {
    public var now: @Sendable () -> Date {
        get { self[NowKey.self] }
        set { self[NowKey.self] = newValue }
    }

    public var uuid: @Sendable () -> UUID {
        get { self[UUIDKey.self] }
        set { self[UUIDKey.self] = newValue }
    }
}
