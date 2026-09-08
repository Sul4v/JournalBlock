import Foundation

/// Gives a new signup today to preview their page. The first morning is set
/// when account and subscription setup finish, even if that took several days.
struct FirstMorningSchedule: Codable, Equatable {
    private var awaitingAccount = false
    private var pendingAccounts: Set<String> = []
    private var startDays: [String: Date] = [:]
    /// Accounts that arrived through the quiz. Only these get the tomorrow
    /// preview; anyone signing in gets the ordinary Today screen, and both get
    /// the gate held off until their first session day.
    private var signupAccounts: Set<String> = []

    init() {}

    /// Tolerant of keys that predate a field, so adding one doesn't throw away
    /// somebody's schedule — and with it their gate-free first day.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        awaitingAccount = try box.decodeIfPresent(Bool.self, forKey: .awaitingAccount) ?? false
        pendingAccounts = try box.decodeIfPresent(Set<String>.self, forKey: .pendingAccounts) ?? []
        startDays = try box.decodeIfPresent([String: Date].self, forKey: .startDays) ?? [:]
        signupAccounts = try box.decodeIfPresent(Set<String>.self, forKey: .signupAccounts) ?? []
    }

    mutating func beginSignup() {
        awaitingAccount = true
    }

    /// True between finishing the quiz and an account claiming it. Read by
    /// `RootView.startSignUp` to tell "this person just built a plan and is
    /// still looking for the sign-up form" apart from "a different person is
    /// starting over on a phone somebody else has used".
    var isAwaitingAccount: Bool { awaitingAccount }

    /// Bind before the paywall so signing out there cannot transfer the
    /// pending first morning to a different account on the same phone.
    mutating func bind(to userID: String) {
        guard awaitingAccount else { return }
        awaitingAccount = false
        if startDays[userID] == nil {
            pendingAccounts.insert(userID)
            signupAccounts.insert(userID)
        }
    }

    /// Every account gets its first session day set the first time it reaches
    /// the app on this device — not only the ones that came through the quiz.
    ///
    /// It used to be signups only, which meant somebody signing in mid-
    /// afternoon was handed the locked gate before they had seen the app,
    /// owing a morning page from a morning they hadn't been here for.
    mutating func beginAccess(
        for userID: String,
        on date: Date = .now,
        calendar: Calendar = .current
    ) {
        bind(to: userID)
        guard startDays[userID] == nil,
              let tomorrow = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: date))
        else { return }
        startDays[userID] = tomorrow
        pendingAccounts.remove(userID)
    }

    /// Before this account's first session day on this device. The gate is
    /// held off until then, however the user got here.
    func isBeforeFirstSession(
        for userID: String?,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let userID else { return false }
        if let start = startDays[userID] {
            return calendar.startOfDay(for: date) < calendar.startOfDay(for: start)
        }
        // Cover the handoff before beginAccess runs, so the journal gate never
        // flashes between the paywall and the first Today screen.
        return awaitingAccount || pendingAccounts.contains(userID)
    }

    /// Shows the tomorrow preview instead of the ordinary Today screen. Only a
    /// fresh signup gets this: someone signing in has a journal already, and
    /// telling them their "first pages are set" would be nonsense.
    func isPreparing(
        for userID: String?,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let userID else { return false }
        guard awaitingAccount || signupAccounts.contains(userID) else { return false }
        return isBeforeFirstSession(for: userID, on: date, calendar: calendar)
    }
}
