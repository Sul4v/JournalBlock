import Foundation
import SwiftData

/// One day's journal. There is at most one entry per calendar day, keyed by
/// `day` (midnight-normalised) so lookups and streaks stay simple.
@Model
final class JournalEntry {
    #Unique<JournalEntry>([\.day])
    #Index<JournalEntry>([\.day])

    var id: UUID = UUID()
    /// Midnight of the day this entry belongs to, in the user's calendar.
    var day: Date = Date.distantPast
    var createdAt: Date = Date.now
    /// Bumped on every write. Backup sync compares this against the server's
    /// `updated_at` to settle which copy of a day wins, so anything that
    /// changes an entry has to touch it — see `JournalStore.touch`.
    var updatedAt: Date = Date.now
    /// The `updatedAt` value that was last successfully backed up. Nil means
    /// this day has never reached the server. Compared against `updatedAt`
    /// rather than being a plain flag, so editing a day that was already
    /// uploaded correctly marks it pending again.
    var backedUpAt: Date?
    /// Set the moment the morning session is finished. This is the flag the
    /// gate reads — nil means the user still owes today's pages.
    var morningCompletedAt: Date?
    var eveningCompletedAt: Date?
    /// 1...5, captured in a single tap at the top of the session.
    var mood: Int?

    @Relationship(deleteRule: .cascade, inverse: \PromptAnswer.entry)
    var answers: [PromptAnswer] = []

    init(day: Date) {
        self.id = UUID()
        self.day = day
        self.createdAt = .now
        self.updatedAt = .now
    }

    var isMorningComplete: Bool { morningCompletedAt != nil }
    var isEveningComplete: Bool { eveningCompletedAt != nil }

    func answers(for session: JournalPrompt.Session) -> [PromptAnswer] {
        answers.filter { $0.session == session }.sorted { $0.order < $1.order }
    }

    /// Everything the user wrote, for previews and search.
    var allLines: [String] {
        answers.sorted { $0.order < $1.order }
            .flatMap(\.lines)
            .filter { !$0.trimmed.isEmpty }
    }
}

/// The user's writing for one prompt on one day.
///
/// Prompt title and hint are *snapshotted* rather than referenced: if the user
/// later reworks their prompts, old entries must still read the way they were written.
@Model
final class PromptAnswer {
    var id: UUID = UUID()
    var promptID: UUID = UUID()
    var promptTitle: String = ""
    var sessionRaw: String = JournalPrompt.Session.morning.rawValue
    var order: Int = 0
    var lines: [String] = []

    var entry: JournalEntry?

    var session: JournalPrompt.Session {
        JournalPrompt.Session(rawValue: sessionRaw) ?? .morning
    }

    var filledLines: [String] { lines.filter { !$0.trimmed.isEmpty } }
    var hasContent: Bool { !filledLines.isEmpty }

    init(prompt: JournalPrompt, lines: [String]) {
        self.id = UUID()
        self.promptID = prompt.id
        self.promptTitle = prompt.title
        self.sessionRaw = prompt.sessionRaw
        self.order = prompt.order
        self.lines = lines
    }

    /// Rebuilds an answer from a decrypted backup, where the prompt it was
    /// written against may no longer exist on this device. The snapshotted
    /// title is the whole reason that still reads correctly.
    init(promptID: UUID, promptTitle: String, sessionRaw: String, order: Int, lines: [String]) {
        self.id = UUID()
        self.promptID = promptID
        self.promptTitle = promptTitle
        self.sessionRaw = sessionRaw
        self.order = order
        self.lines = lines
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
