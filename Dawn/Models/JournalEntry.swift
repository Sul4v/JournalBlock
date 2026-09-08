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
    /// Set the moment the morning session is finished.
    ///
    /// Superseded by `completions`, and kept for two reasons: a backup written
    /// by a pre-blocks build carries these and nothing else, and the migration
    /// that turns the old fixed pair into blocks reads them to work out which
    /// days were already done.
    var morningCompletedAt: Date?
    var eveningCompletedAt: Date?

    /// When each block was finished today. One encoded array rather than a
    /// child model: the list is at most a handful of rows, is only ever read
    /// whole, and a relationship would have meant a third table to keep in step
    /// with backup.
    var completions: [BlockCompletion] = []
    /// Legacy check-in value retained for existing stores and backup compatibility.
    /// No longer collected or displayed.
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

    // MARK: - Blocks

    func completedAt(_ blockID: UUID) -> Date? {
        completions.first { $0.blockID == blockID }?.at
    }

    func isComplete(_ blockID: UUID) -> Bool { completedAt(blockID) != nil }

    /// What the streak counts. Any block written is a day the user showed up —
    /// someone whose only sitting is at 9pm has kept the habit as surely as
    /// someone who writes at dawn.
    var isAnyBlockComplete: Bool { !completions.isEmpty }

    func markComplete(_ blockID: UUID, at date: Date = .now) {
        if let index = completions.firstIndex(where: { $0.blockID == blockID }) {
            completions[index].at = date
        } else {
            completions.append(BlockCompletion(blockID: blockID, at: date))
        }
    }

    func answers(for session: JournalPrompt.Session) -> [PromptAnswer] {
        answers.filter { $0.session == session }.sorted { $0.order < $1.order }
    }

    func answers(forBlock blockID: UUID) -> [PromptAnswer] {
        answers.filter { $0.blockID == blockID }.sorted { $0.order < $1.order }
    }

    /// Every answer grouped by the block it was written in, in the order the
    /// blocks were answered — the reading order for a day in history, which
    /// must not depend on blocks the user may since have deleted or retimed.
    var answersByBlock: [(blockID: UUID, title: String, answers: [PromptAnswer])] {
        var seen: [UUID] = []
        for answer in answers.sorted(by: { $0.order < $1.order })
        where !seen.contains(answer.blockID) {
            seen.append(answer.blockID)
        }
        return seen.map { id in
            let group = answers(forBlock: id)
            return (id, group.first?.blockTitle ?? "", group)
        }
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
    /// The block this was written in, and its name at the time.
    ///
    /// Snapshotted for the same reason `promptTitle` is: the user can rename
    /// "Morning" to "Before the noise" or delete the block outright, and a day
    /// already written has to keep reading the way it was written.
    var blockID: UUID = UUID()
    var blockTitle: String = ""
    var order: Int = 0
    var lines: [String] = []

    var entry: JournalEntry?

    var session: JournalPrompt.Session {
        JournalPrompt.Session(rawValue: sessionRaw) ?? .morning
    }

    var filledLines: [String] { lines.filter { !$0.trimmed.isEmpty } }
    var hasContent: Bool { !filledLines.isEmpty }

    init(prompt: JournalPrompt, blockTitle: String, lines: [String]) {
        self.id = UUID()
        self.promptID = prompt.id
        self.promptTitle = prompt.title
        self.sessionRaw = prompt.sessionRaw
        self.blockID = prompt.blockID
        self.blockTitle = blockTitle
        self.order = prompt.order
        self.lines = lines
    }

    /// Rebuilds an answer from a decrypted backup, where the prompt it was
    /// written against may no longer exist on this device. The snapshotted
    /// title is the whole reason that still reads correctly.
    init(
        promptID: UUID,
        promptTitle: String,
        sessionRaw: String,
        blockID: UUID,
        blockTitle: String,
        order: Int,
        lines: [String]
    ) {
        self.id = UUID()
        self.promptID = promptID
        self.promptTitle = promptTitle
        self.sessionRaw = sessionRaw
        self.blockID = blockID
        self.blockTitle = blockTitle
        self.order = order
        self.lines = lines
    }
}

/// One block finished on one day.
struct BlockCompletion: Codable, Equatable, Hashable {
    var blockID: UUID
    var at: Date
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
