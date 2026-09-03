import Foundation

/// The plaintext shape of one day, as it exists only in memory and inside
/// ciphertext. Everything a person actually wrote lives in here — text, mood,
/// prompt titles — so that the row in Postgres can be nothing but a date and
/// an opaque blob.
struct EntryPayload: Codable {
    struct Answer: Codable {
        var promptID: UUID
        var promptTitle: String
        var session: String
        var order: Int
        var lines: [String]
    }

    /// Lets a future format change be detected rather than mis-parsed.
    var schema: Int = 1
    var createdAt: Date
    var mood: Int?
    var morningCompletedAt: Date?
    var eveningCompletedAt: Date?
    var answers: [Answer]

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Converts between the app's local-midnight `Date` and the `yyyy-MM-dd` the
/// server stores.
///
/// Deliberately formatted in the user's own calendar rather than UTC: the day
/// an entry belongs to is the day they lived, and a UTC round trip would shunt
/// every evening entry east of London onto tomorrow.
enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from day: Date) -> String {
        formatter.string(from: day)
    }

    static func date(from string: String) -> Date? {
        guard let parsed = formatter.date(from: string) else { return nil }
        return Calendar.current.startOfDay(for: parsed)
    }
}
