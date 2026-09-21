import Foundation

public enum PersistenceError: Error, Sendable {
    case io(path: String, underlying: String)
    case corrupt(path: String, reason: String)
    case unsupportedVersion(path: String, found: Int, supported: Int)
}

extension PersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .io(path, underlying): "io error at \(path): \(underlying)"
        case let .corrupt(path, reason): "corrupt file \(path): \(reason)"
        case let .unsupportedVersion(path, found, supported):
            "\(path) has format version \(found); this build supports \(supported)"
        }
    }
}
