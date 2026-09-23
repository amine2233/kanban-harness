import DashboardDomain
import DashboardPersistence
import Testing
@testable import DashboardService

@Suite
struct SettingsServiceTests {
    @Test
    func currentStartsWithDefaults() async throws {
        let svc = SettingsService(store: InMemorySettingsStore())
        #expect(try await svc.current() == .default)
    }

    @Test
    func updateMergesValidatesAndPersists() async throws {
        let svc = SettingsService(store: InMemorySettingsStore())
        let updated = try await svc.update(corsOrigins: ["http://localhost:5173/"])
        #expect(updated == Settings(defaultStorage: .json, corsOrigins: ["http://localhost:5173"]))
        let again = try await svc.update(defaultStorage: .sqlite)
        #expect(again.corsOrigins == ["http://localhost:5173"], "untouched fields are kept")
        #expect(again.defaultStorage == .sqlite)
        #expect(try await svc.current() == again)
    }

    @Test
    func updateWithBadOriginIsValidationErrorAndChangesNothing() async throws {
        let svc = SettingsService(store: InMemorySettingsStore())
        do {
            _ = try await svc.update(corsOrigins: ["ftp://x"])
            Issue.record("expected error")
        } catch {
            #expect(error.isValidation)
        }
        #expect(try await svc.current() == .default)
    }
}
