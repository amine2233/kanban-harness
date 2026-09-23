import Foundation

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

/// Which build this process is.
///
/// Upgrading the binary leaves the old daemon running, and it keeps answering
/// on the same port; without an identity on the wire the new binary talks to it
/// and neither side can tell.
public enum DashboardVersion {
    /// ponytail: hand-written, and rarely bumped — the build stamp below is what
    /// actually separates two processes during development.
    static let declared = "0.1.0"

    /// The declared version plus the executable's modification time, so a rebuild
    /// counts as a different version too.
    ///
    /// Computed once per process. A daemon must therefore read it while it starts
    /// — see `routes` — or an upgrade that replaces the file on disk would make it
    /// report the *new* version and the skew would go unnoticed.
    public static let current: String = {
        guard let path = Bundle.main.executablePath,
              let modified = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        else { return declared }
        return "\(declared)+\(Int(modified.timeIntervalSince1970))"
    }()
}
