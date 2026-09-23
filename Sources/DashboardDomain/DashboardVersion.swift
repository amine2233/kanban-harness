import Foundation

/// What this build calls itself. The one copy: `dashboard --version`, the MCP
/// handshake and `/api/health` all read it here.
public enum DashboardVersion {
    /// The product version, as `dashboard --version` prints it.
    public static let declared = "0.1.0"

    /// `declared` plus the executable's modification time, so a rebuild counts as
    /// a different build too — that is the skew a developer actually meets, and it
    /// does not bump a version string.
    ///
    /// `Bundle.main` is the running executable on both platforms, which is what
    /// has to be identified; `Bundle.module` is a target's resource bundle and
    /// exists only for targets that declare resources.
    ///
    /// Computed once per process. A daemon must therefore read it while it starts,
    /// or an upgrade that replaces the file on disk would make it report the *new*
    /// build and the skew would go unnoticed.
    public static let current: String = {
        guard let path = Bundle.main.executablePath,
              let modified = try? FileManager.default
              .attributesOfItem(atPath: path)[.modificationDate] as? Date
        else { return declared }

        return "\(declared)+\(Int(modified.timeIntervalSince1970))"
    }()
}
