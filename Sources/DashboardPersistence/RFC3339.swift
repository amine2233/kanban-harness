import Foundation

/// kanban-rs (chrono) timestamps: `2026-09-19T08:56:45.318377Z`. Parses any
/// number of fractional digits, writes six; dates the domain creates are
/// quantized to microseconds (`Date.timestamp()`) so they round-trip exactly.
public enum RFC3339 {
    private static let base = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    public static func parse(_ text: String) -> Date? {
        guard let dot = text.firstIndex(of: ".") else { return try? base.parse(text) }
        let fraction = text[text.index(after: dot)...].prefix { $0.isNumber }
        let rest = text[text.index(dot, offsetBy: 1 + fraction.count)...]
        guard let whole = try? base.parse(String(text[..<dot]) + rest),
              let digits = Double("0." + fraction)
        else { return nil }
        // Whole seconds + fraction, the same arithmetic as `Date.quantizedToMicroseconds`.
        return Date(timeIntervalSince1970: whole.timeIntervalSince1970 + digits)
    }

    public static func format(_ date: Date) -> String {
        let seconds = date.timeIntervalSince1970
        let whole = seconds.rounded(.down)
        let micros = Int(((seconds - whole) * 1_000_000).rounded())
        let text = Date(timeIntervalSince1970: whole).formatted(base)
        return text.replacingOccurrences(of: "Z", with: String(format: ".%06dZ", micros))
    }

    public static func configure(_ decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "invalid timestamp '\(text)'")
                )
            }
            return date
        }
    }

    public static func configure(_ encoder: JSONEncoder) {
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
    }
}
