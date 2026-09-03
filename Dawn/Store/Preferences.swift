import Foundation
import Observation
import SwiftUI

/// App-level settings. Small enough to live in UserDefaults; observable so the
/// gate re-evaluates the moment anything changes.
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        self.displayName = defaults.string(forKey: Key.displayName) ?? ""
        self.strictMode = defaults.object(forKey: Key.strictMode) as? Bool ?? true
        self.blockAppsUntilDone = defaults.object(forKey: Key.blockApps) as? Bool ?? false
        self.alarmEnabled = defaults.object(forKey: Key.alarmEnabled) as? Bool ?? false
        self.eveningPromptsEnabled = defaults.object(forKey: Key.eveningEnabled) as? Bool ?? true
        self.wakeHour = defaults.object(forKey: Key.wakeHour) as? Int ?? 7
        self.wakeMinute = defaults.object(forKey: Key.wakeMinute) as? Int ?? 0
        self.quizAnswers = Self.loadQuiz(from: defaults)
        self.hasCompletedQuiz = defaults.bool(forKey: Key.hasCompletedQuiz)
        self.hasEverSignedIn = defaults.bool(forKey: Key.hasEverSignedIn)
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(Theme.Appearance.init(rawValue:)) ?? .system
    }

    // MARK: Stored

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    var displayName: String { didSet { defaults.set(displayName, forKey: Key.displayName) } }

    /// When on, the morning gate cannot be dismissed. This is the whole premise
    /// of the app, so it defaults on.
    var strictMode: Bool { didSet { defaults.set(strictMode, forKey: Key.strictMode) } }

    /// Extends the gate to the rest of the phone via Screen Time shields.
    var blockAppsUntilDone: Bool { didSet { defaults.set(blockAppsUntilDone, forKey: Key.blockApps) } }

    /// Light, dark, or follow iOS. Defaults to `.system`, so a new install
    /// matches whatever the phone is already doing rather than announcing an
    /// opinion — and keeps tracking it if the user changes it later.
    var appearance: Theme.Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var alarmEnabled: Bool { didSet { defaults.set(alarmEnabled, forKey: Key.alarmEnabled) } }
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
            strictMode: strictMode,
            blockAppsUntilDone: blockAppsUntilDone,
            appearance: appearance.rawValue,
            alarmEnabled: alarmEnabled,
            eveningPromptsEnabled: eveningPromptsEnabled,
            wakeHour: wakeHour,
            wakeMinute: wakeMinute,
            quizAnswers: quizAnswers
        )
    }

    func apply(_ snapshot: SettingsPayload.Settings) {
        displayName = snapshot.displayName
        strictMode = snapshot.strictMode
        blockAppsUntilDone = snapshot.blockAppsUntilDone
        appearance = Theme.Appearance(rawValue: snapshot.appearance) ?? .system
        alarmEnabled = snapshot.alarmEnabled
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
        displayName = ""
        quizAnswers = QuizAnswers()
        strictMode = true
        blockAppsUntilDone = false
        alarmEnabled = false
        eveningPromptsEnabled = true
        appearance = .system
        wakeHour = 7
        wakeMinute = 0
    }

    private enum Key {
        static let hasOnboarded = "dawn.hasOnboarded"
        static let displayName = "dawn.displayName"
        static let strictMode = "dawn.strictMode"
        static let blockApps = "dawn.blockAppsUntilDone"
        static let alarmEnabled = "dawn.alarmEnabled"
        static let eveningEnabled = "dawn.eveningPromptsEnabled"
        static let wakeHour = "dawn.wakeHour"
        static let wakeMinute = "dawn.wakeMinute"
        static let quizAnswers = "dawn.quizAnswers"
        static let hasCompletedQuiz = "dawn.hasCompletedQuiz"
        static let hasEverSignedIn = "dawn.hasEverSignedIn"
        static let appearance = "dawn.appearance"

        static let all = [
            hasOnboarded, displayName, strictMode, blockApps,
            alarmEnabled, eveningEnabled, wakeHour, wakeMinute,
            quizAnswers, hasCompletedQuiz, hasEverSignedIn, appearance
        ]
    }
}
