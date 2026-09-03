import Foundation

/// Parses and formats the `timestamptz` values that ride on backup rows.
///
/// Hand-rolled rather than handed to `ISO8601DateFormatter` directly because
/// Postgres emits microseconds (`.123456`) and that formatter refuses anything
/// other than exactly three fractional digits — it returns nil rather than
/// rounding, which would silently break every last-write-wins comparison.
enum PostgresTimestamp {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let normalized = truncatingFraction(string)
        return withFraction.date(from: normalized) ?? plain.date(from: normalized)
    }

    /// Cuts the fractional part down to three digits and leaves the zone suffix
    /// alone. Postgres also returns `+00` where ISO 8601 wants `+00:00`.
    private static func truncatingFraction(_ input: String) -> String {
        var result = input
        if let dot = result.firstIndex(of: ".") {
            let after = result.index(after: dot)
            let digits = result[after...].prefix { $0.isNumber }
            if digits.count > 3 {
                let cutFrom = result.index(after, offsetBy: 3)
                let cutTo = result.index(after, offsetBy: digits.count)
                result.removeSubrange(cutFrom..<cutTo)
            }
        }
        if result.hasSuffix("+00") { result = String(result.dropLast(3)) + "+00:00" }
        return result
    }
}
