import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Crash-safe file writes: temp file in the same directory, then `rename(2)`
/// (works on Darwin and Linux alike, unlike `FileManager.replaceItemAt`).
public enum AtomicFile {
    /// Nil when the file does not exist (checked up front: the "no such file"
    /// error is a CocoaError on Darwin and a POSIX error on Linux).
    public static func read(_ path: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
    }

    /// `mode` is applied to the temp file before the rename, so the final file never exists with wider
    /// permissions.
    public static func write(_ data: Data, to path: String, mode: Int? = nil) throws {
        let directory = (path as NSString).deletingLastPathComponent
        let temp = path + ".tmp"
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: temp))
            if let mode {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temp)
            }
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
        guard rename(temp, path) == 0 else {
            throw PersistenceError.io(path: path, underlying: String(cString: strerror(errno)))
        }
    }
}
