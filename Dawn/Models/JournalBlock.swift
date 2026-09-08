import Foundation
import SwiftData

/// One sitting in the user's day: a time, and the prompts they answer at it.
///
/// Replaces the fixed morning/evening pair. That pair was a guess about how
/// people use the app, and it was wrong in both directions — it forced an
/// evening reflection on people who only wanted a morning page, and gave no
/// room at all to someone who wanted a midday check-in. A block is the same
/// idea with the number left to the user.
///
/// `JournalPrompt.Session` survives as a raw string on prompts and answers so
/// that backups written by older builds still decode; nothing in the app reads
/// it to decide behaviour any more.
@Model
final class JournalBlock {
    #Index<JournalBlock>([\.order])

    var id: UUID = UUID()
    /// What the hour is usually called — "Morning", "Midday", "Night".
    ///
    /// No longer a name the user gives or sees: a block is designated by its
    /// time everywhere in the app, and `timeLabel` is what gets shown. This
    /// stays, derived from `hour` and kept in step by `JournalStore.setTime`,
    /// for the two places a bare word is still the only thing available: a
    /// backup decoded by a build that predates this change, and the answers
    /// already written into `PromptAnswer.blockTitle`.
    var title: String = ""
    var hour: Int = 7
    var minute: Int = 0
    /// Tiebreaker only. Blocks read in time order; `order` settles two blocks
    /// scheduled at the same minute.
    var order: Int = 0

    /// Locks the phone until this block is written.
    ///
    /// True for every block that has a question to ask, and no longer a choice
    /// the user makes: a sitting that doesn't hold the door shut is a reminder,
    /// and this app is the door. The way out of a lock is to delete the block,
    /// or to turn off strict mode, which puts a skip on all of them at once.
    ///
    /// Still stored rather than computed — it rides in backups, and an empty
    /// block must not gate, which `JournalStore.repairLibraryIfNeeded` and
    /// `addPrompt` keep true between them.
    var gatesDay: Bool = true

    /// A local notification at this block's time. Separate from the wake alarm,
    /// which rings through silent mode and belongs to the gate alone.
    ///
    /// On for every block, for the same reason as `gatesDay`: a time you have
    /// committed to write at is a time worth being told about. Someone who
    /// wants silence has iOS's own notification settings.
    var remindersEnabled: Bool = true

    /// `"morning"` or `"evening"` for the two blocks migrated from the old
    /// fixed pair, empty for anything the user made. Backup compatibility only.
    var legacySessionRaw: String = ""

    init(
        title: String,
        hour: Int,
        minute: Int = 0,
        order: Int = 0,
        gatesDay: Bool = true,
        remindersEnabled: Bool = true,
        legacySession: JournalPrompt.Session? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.hour = hour
        self.minute = minute
        self.order = order
        self.gatesDay = gatesDay
        self.remindersEnabled = remindersEnabled
        self.legacySessionRaw = legacySession?.rawValue ?? ""
    }

    // MARK: - Time

    /// Minutes since midnight. The sort key for a day, and what "is this block
    /// due yet" compares against.
    var minutesOfDay: Int { hour * 60 + minute }

    var time: DateComponents { DateComponents(hour: hour, minute: minute) }

    /// This block's time on a given day, for display and scheduling.
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// "7:00 AM", in the user's locale and clock.
    var timeLabel: String {
        date().formatted(.dateTime.hour().minute())
    }

    func setTime(from date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? hour
        minute = parts.minute ?? minute
    }

    var icon: String { Self.icon(forHour: hour) }

    // MARK: - Defaults

    /// What an hour of the day is usually called. Nothing in the app shows
    /// this any more — see `title`, which it feeds.
    static func defaultTitle(forHour hour: Int) -> String {
        switch hour {
        case 0..<5: "Night"
        case 5..<11: "Morning"
        case 11..<14: "Midday"
        case 14..<18: "Afternoon"
        case 18..<21: "Evening"
        default: "Night"
        }
    }

    static func icon(forHour hour: Int) -> String {
        switch hour {
        case 0..<5: "moon.stars"
        case 5..<11: "sun.horizon"
        case 11..<16: "sun.max"
        case 16..<20: "sunset"
        default: "moon.stars"
        }
    }
}
