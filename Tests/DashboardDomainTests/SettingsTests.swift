import Foundation
import Testing
@testable import DashboardDomain

@Suite
struct SettingsTests {
    @Test
    func normaliseOriginAcceptsHttpAndHttpsWithOptionalPort() throws {
        #expect(try Settings.normaliseOrigin(" HTTP://LocalHost:5173/ ") == "http://localhost:5173")
        #expect(try Settings.normaliseOrigin("https://app.example.com") == "https://app.example.com")
    }

    @Test
    func normaliseOriginRejectsPathsSchemesAndGarbage() {
        for bad in ["ftp://x", "http://host/path", "http://host?x=1", "not an origin", ""] {
            #expect(throws: DomainError.self, "\(bad)") { try Settings.normaliseOrigin(bad) }
        }
    }

    @Test
    func validatedNormalisesAndDeduplicatesOrigins() throws {
        let settings = Settings(
            defaultStorage: .sqlite,
            corsOrigins: ["http://a:1/", "http://A:1", "https://b"]
        )
        #expect(try settings.validated() == Settings(
            defaultStorage: .sqlite,
            corsOrigins: ["http://a:1", "https://b"]
        ))
    }

    @Test
    func decodesMissingKeysAsDefaults() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings == .default)
        let partial = try JSONDecoder().decode(
            Settings.self,
            from: Data(#"{"default_storage":"sqlite"}"#.utf8)
        )
        #expect(partial.defaultStorage == .sqlite)
        #expect(partial.corsOrigins.isEmpty)
    }
}
