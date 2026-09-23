import DashboardDomain

/// What `/api/health` answers: that the owner is alive, and which build it is.
///
/// `version` is absent from a daemon older than this field; a client reads that
/// as a mismatch, which is the right answer — an old daemon is exactly what it
/// is looking for.
public struct HealthResponse: Codable, Sendable, Equatable {
    public var status: String
    public var version: String?

    public init(status: String = "ok", version: String? = DashboardVersion.current) {
        self.status = status
        self.version = version
    }
}
