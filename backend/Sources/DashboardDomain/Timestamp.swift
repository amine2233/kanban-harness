import Foundation

extension Date {
    /// "Now" at the precision the files keep (microseconds, like kanban-rs
    /// timestamps), so a value survives a save/load unchanged. Linux clocks
    /// hand out nanoseconds; a raw `Date()` would come back different.
    public static func timestamp() -> Date {
        Date().quantizedToMicroseconds
    }

    /// Built as whole seconds + microseconds / 1e6 — the same arithmetic the
    /// RFC 3339 parser uses, so the double comes out bit-identical after a round trip.
    public var quantizedToMicroseconds: Date {
        let whole = timeIntervalSince1970.rounded(.down)
        let micros = ((timeIntervalSince1970 - whole) * 1_000_000).rounded()
        return Date(timeIntervalSince1970: whole + micros / 1_000_000)
    }
}
