import ArgumentParser
import DashboardPersistenceJSON
import Foundation

enum Output {
    static func json(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        RFC3339.configure(encoder)
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}

extension AsyncParsableCommand {
    /// Runs `body`; a failure becomes a JSON envelope on stderr and exit code 1.
    func failing(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let envelope = try JSONSerialization.data(withJSONObject: ["error": ["message": message]])
            FileHandle.standardError.write(envelope)
            FileHandle.standardError.write(Data("\n".utf8))
            throw ExitCode.failure
        }
    }
}
