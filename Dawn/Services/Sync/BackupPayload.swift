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

        // Added in schema 2, when the fixed morning/evening pair became blocks.
        // Optional rather than defaulted: a v1 payload genuinely doesn't know
        // which block an answer belongs to, and the restore has to be able to
        // tell "no block recorded" from "block id happens to be all zeroes".
        var blockID: UUID?
        var blockTitle: String?
    }

    /// Lets a future format change be detected rather than mis-parsed.
    /// 2 since days record which blocks were finished rather than just a
    /// morning and an evening.
    var schema: Int = 2
    var createdAt: Date
    /// Legacy check-in value, preserved when syncing older entries.
    var mood: Int?
    /// Still written in schema 2, so a phone on the old build that pulls this
    /// day down keeps a working gate. See `JournalStore.stamp`.
    var morningCompletedAt: Date?
    var eveningCompletedAt: Date?
    var completions: [BlockCompletion]?
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
