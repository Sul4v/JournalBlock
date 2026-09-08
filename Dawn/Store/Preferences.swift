import Foundation
import Observation
import SwiftUI

/// App-level settings. Small enough to live in UserDefaults; observable so the
/// gate re-evaluates the moment anything changes.
/// How every block asks for its page.
///
/// Replaces a pair of independent switches — "Wake alarm" and "Block other
/// apps" — which could be set to all four combinations, two of which meant
/// nothing: an app that neither rings nor blocks is a journal with a schedule,
/// and one that does both was never asked for. These are the two answers that
/// carry weight.
enum GateMode: String, CaseIterable, Sendable {
    /// An alarm at the block's time, re-armed until the page is written.
    /// Rings through silent mode and Focus; leaves the rest of the phone alone.
    case alarm
    /// A notification at the block's time, and every other app shielded until
    /// the page is written.
    case reminder

    var label: String {
        switch self {
        case .alarm: "Alarm"
        case .reminder: "Reminder"
        }
    }

    var detail: String {
        switch self {
        case .alarm: "Rings at each block's time, through silent mode and Focus, and keeps ringing until the page is written."
        case .reminder: "A notification at each block's time, and every other app stays shut until the page is written."
        }
    }

    var symbol: String {
        switch self {
        case .alarm: "alarm"
        case .reminder: "bell.badge"
        }
    }
}

@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        self.displayName = defaults.string(forKey: Key.displayName) ?? ""
        // Migrated from the two switches this replaced: anyone who had the
        // shield on keeps it, anyone who only had the alarm keeps that, and a
        // fresh install starts on the mode that actually holds the door.
        if let raw = defaults.string(forKey: Key.gateMode), let mode = GateMode(rawValue: raw) {
            self.gateMode = mode
        } else if defaults.object(forKey: Key.blockApps) as? Bool == true {
            self.gateMode = .reminder
        } else if defaults.object(forKey: Key.alarmEnabled) as? Bool == true {
            self.gateMode = .alarm
        } else {
            self.gateMode = .reminder
        }
        self.eveningPromptsEnabled = defaults.object(forKey: Key.eveningEnabled) as? Bool ?? true
        self.wakeHour = defaults.object(forKey: Key.wakeHour) as? Int ?? 7
        self.wakeMinute = defaults.object(forKey: Key.wakeMinute) as? Int ?? 0
        self.quizAnswers = Self.loadQuiz(from: defaults)
        self.hasCompletedQuiz = defaults.bool(forKey: Key.hasCompletedQuiz)
        self.hasEverSignedIn = defaults.bool(forKey: Key.hasEverSignedIn)
        self.hasPrimedPermissions = defaults.bool(forKey: Key.hasPrimedPermissions)
        self.firstMorningSchedule = defaults.data(forKey: Key.firstMorningSchedule)
            .flatMap { try? JSONDecoder().decode(FirstMorningSchedule.self, from: $0) }
            ?? FirstMorningSchedule()
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(Theme.Appearance.init(rawValue:)) ?? .system
    }

    // MARK: Stored

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    var displayName: String { didSet { defaults.set(displayName, forKey: Key.displayName) } }

    /// How a block asks for the page: by ringing, or by shutting the phone.
    ///
    /// One setting where there were two switches, because the two were never
    /// independent in the user's head — "wake me" and "stop me" are the same
    /// question answered differently.
    var gateMode: GateMode { didSet { defaults.set(gateMode.rawValue, forKey: Key.gateMode) } }

    /// Shields every app until the block is written. True in reminder mode
    /// only — an alarm that also took the phone away would be both modes.
    var blockAppsUntilDone: Bool { gateMode == .reminder }

    /// True once the permission primer after the paywall has been seen — not
    /// once permission was *granted*. Someone who declined has answered the
    /// question, and asking again on every launch is how an app trains people
    /// to deny it on sight. Settings is where they change their mind.
    var hasPrimedPermissions: Bool {
        didSet { defaults.set(hasPrimedPermissions, forKey: Key.hasPrimedPermissions) }
    }

    /// Light, dark, or follow iOS. Defaults to `.system`, so a new install
    /// matches whatever the phone is already doing rather than announcing an
    /// opinion — and keeps tracking it if the user changes it later.
    var appearance: Theme.Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Rings at every block's time until that block is written. True in alarm
    /// mode only.
    var alarmEnabled: Bool { gateMode == .alarm }
    /// Legacy. Blocks replaced it: an evening sitting is now a block the user
    /// keeps or deletes like any other. Still stored and still backed up, so
    /// that the one-time migration to blocks can honour someone who had it
    /// switched off — see `JournalStore.migrateToBlocksIfNeeded` — and so a
    /// phone still on the old build reads a sane value.
    var eveningPromptsEnabled: Bool { didSet { defaults.set(eveningPromptsEnabled, forKey: Key.eveningEnabled) } }

    /// The personalisation quiz. Answers outlive onboarding — the plan
    /// screen, the paywall headline, and the prompt set all read from them.
    var quizAnswers: QuizAnswers {
        didSet {
            guard let data = try? JSONEncoder().encode(quizAnswers) else { return }
            defaults.set(data, forKey: Key.quizAnswers)
        }
    }

    /// Onboarding is finished once the quiz is done; account and subscription
    /// are separate gates that follow it.
    var hasCompletedQuiz: Bool { didSet { defaults.set(hasCompletedQuiz, forKey: Key.hasCompletedQuiz) } }

    /// Local onboarding state, kept per account and excluded from backup.
    var firstMorningSchedule: FirstMorningSchedule {
        didSet {
            guard let data = try? JSONEncoder().encode(firstMorningSchedule) else { return }
            defaults.set(data, forKey: Key.firstMorningSchedule)
        }
    }

    /// Puts the quiz back in front of someone creating a second account on this
    /// phone. The answers describe the person behind the account that just left,
    /// so the plan, the paywall headline and the prompt set all have to be asked
    /// again rather than inherited.
    func restartQuiz() {
        quizAnswers = QuizAnswers()
        hasCompletedQuiz = false
    }

    /// Set the first time an account is created or signed into. After a sign
    /// out this is what tells the auth screen to greet a returning user rather
    /// than pitch them the sign-up flow again.
    var hasEverSignedIn: Bool { didSet { defaults.set(hasEverSignedIn, forKey: Key.hasEverSignedIn) } }

    var wakeHour: Int { didSet { defaults.set(wakeHour, forKey: Key.wakeHour) } }
    var wakeMinute: Int { didSet { defaults.set(wakeMinute, forKey: Key.wakeMinute) } }

    // MARK: Derived

    var wakeTime: DateComponents {
        DateComponents(hour: wakeHour, minute: wakeMinute)
    }

    /// The wake time rendered onto today's date, for display and scheduling.
    func wakeDate(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: wakeHour, minute: wakeMinute, second: 0, of: day
        ) ?? day
    }

    var greetingName: String {
        let name = displayName.trimmed
        return name.isEmpty ? "" : ", \(name)"
    }

    private static func loadQuiz(from defaults: UserDefaults) -> QuizAnswers {
        guard let data = defaults.data(forKey: Key.quizAnswers),
              let decoded = try? JSONDecoder().decode(QuizAnswers.self, from: data)
        else { return QuizAnswers() }
        return decoded
    }

    // MARK: - Backup

    /// The subset worth carrying to another phone. See `SettingsPayload.Settings`
    /// for why onboarding flags are left out.
    var backupSnapshot: SettingsPayload.Settings {
        SettingsPayload.Settings(
            displayName: displayName,
            // Always on. Kept in the payload so a backup written here still
            // decodes on a build that predates the switch being removed.
            strictMode: true,
            blockAppsUntilDone: blockAppsUntilDone,
            appearance: appearance.rawValue,
            alarmEnabled: alarmEnabled,
            eveningPromptsEnabled: eveningPromptsEnabled,
            wakeHour: wakeHour,
            wakeMinute: wakeMinute,
            quizAnswers: quizAnswers,
            gateMode: gateMode.rawValue
        )
    }

    func apply(_ snapshot: SettingsPayload.Settings) {
        displayName = snapshot.displayName
        gateMode = snapshot.gateMode.flatMap(GateMode.init(rawValue:))
            ?? (snapshot.blockAppsUntilDone ? .reminder : .alarm)
        appearance = Theme.Appearance(rawValue: snapshot.appearance) ?? .system
        eveningPromptsEnabled = snapshot.eveningPromptsEnabled
        wakeHour = snapshot.wakeHour
        wakeMinute = snapshot.wakeMinute
        quizAnswers = snapshot.quizAnswers
    }

    /// Clears what identifies a person, leaving the flow flags alone — the new
    /// user is already signed in, and resetting `hasCompletedQuiz` here would
    /// bounce them back into onboarding mid-session.
    func clearPersonalDetails() {
        displayName = ""
        quizAnswers = QuizAnswers()
    }

    /// Wipes everything device-local. Used when deleting an account so the next
    /// person to open the app doesn't inherit the last one's settings.
    func resetAll() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        hasOnboarded = false
        hasCompletedQuiz = false
        hasEverSignedIn = false
        hasPrimedPermissions = false
        firstMorningSchedule = FirstMorningSchedule()
        displayName = ""
        quizAnswers = QuizAnswers()
        gateMode = .reminder
        eveningPromptsEnabled = true
        appearance = .system
        wakeHour = 7
        wakeMinute = 0
    }

    private enum Key {
        static let hasOnboarded = "dawn.hasOnboarded"
        static let displayName = "dawn.displayName"
        static let blockApps = "dawn.blockAppsUntilDone"
        static let gateMode = "dawn.gateMode"
        static let alarmEnabled = "dawn.alarmEnabled"
        static let eveningEnabled = "dawn.eveningPromptsEnabled"
        static let wakeHour = "dawn.wakeHour"
        static let wakeMinute = "dawn.wakeMinute"
        static let quizAnswers = "dawn.quizAnswers"
        static let hasCompletedQuiz = "dawn.hasCompletedQuiz"
        static let hasEverSignedIn = "dawn.hasEverSignedIn"
        static let firstMorningSchedule = "dawn.firstMorningSchedule"
        static let appearance = "dawn.appearance"
        static let hasPrimedPermissions = "dawn.hasPrimedPermissions"

        static let all = [
            hasOnboarded, displayName, blockApps, gateMode,
            alarmEnabled, eveningEnabled, wakeHour, wakeMinute,
            quizAnswers, hasCompletedQuiz, hasEverSignedIn, appearance, firstMorningSchedule,
            hasPrimedPermissions
        ]
    }
}
