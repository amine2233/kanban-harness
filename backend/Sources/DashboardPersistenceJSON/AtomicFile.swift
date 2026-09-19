import DashboardPersistence
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Crash-safe file writes: temp file in the same directory, then `rename(2)`.
enum AtomicFile {
    static func read(_ path: String) throws -> Data? {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
    }

    static func write(_ data: Data, to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        let temp = path + ".tmp"
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: temp))
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
        guard rename(temp, path) == 0 else {
            throw PersistenceError.io(path: path, underlying: String(cString: strerror(errno)))
        }
    }
}
