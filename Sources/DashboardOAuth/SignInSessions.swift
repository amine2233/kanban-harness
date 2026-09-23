import DashboardDomain
import Foundation

/// Sign-ins in flight: `state` → what the callback needs. One-shot and
/// short-lived, so a replayed or forged callback finds nothing.
public actor SignInSessions {
    public struct Pending: Sendable, Equatable {
        public let providerId: String
        public let codeVerifier: String
        public let callback: URL
        public let startedAt: Date
    }

    private var pending: [String: Pending] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(ttl: TimeInterval = 600, now: @escaping @Sendable () -> Date = { .timestamp() }) {
        self.ttl = ttl
        self.now = now
    }

    public func begin(providerId: String, callback: URL) -> (state: String, codeVerifier: String) {
        expire()
        let state = PKCE.state()
        let verifier = PKCE.verifier()
        pending[state] = Pending(
            providerId: providerId,
            codeVerifier: verifier,
            callback: callback,
            startedAt: now()
        )
        return (state, verifier)
    }

    /// Removes and returns the session for `state`; nil when unknown or expired.
    public func consume(_ state: String) -> Pending? {
        expire()
        return pending.removeValue(forKey: state)
    }

    private func expire() {
        let cutoff = now().addingTimeInterval(-ttl)
        pending = pending.filter { $0.value.startedAt > cutoff }
    }
}
