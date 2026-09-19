import Foundation
import Testing
import DashboardPersistence

@Suite struct RFC3339Tests {
    @Test func parsesChronoMicrosecondTimestamps() throws {
        let date = try #require(RFC3339.parse("2026-09-19T08:56:45.318377Z"))
        #expect(abs(date.timeIntervalSince1970 - 1_789_808_205.318377) < 0.000_001)
    }

    @Test func parsesWithoutFractionAndRejectsGarbage() {
        #expect(RFC3339.parse("1970-01-01T00:00:01Z")?.timeIntervalSince1970 == 1)
        #expect(RFC3339.parse("not a date") == nil)
    }

    @Test func formatWritesSixFractionalDigits() {
        #expect(RFC3339.format(Date(timeIntervalSince1970: 1.5)) == "1970-01-01T00:00:01.500000Z")
        #expect(RFC3339.format(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000000Z")
    }

    @Test func formatThenParseRoundTripsToTheMicrosecond() throws {
        let original = Date(timeIntervalSince1970: 1_789_808_205.318377)
        let parsed = try #require(RFC3339.parse(RFC3339.format(original)))
        #expect(abs(parsed.timeIntervalSince1970 - original.timeIntervalSince1970) < 0.000_001)
    }
}
