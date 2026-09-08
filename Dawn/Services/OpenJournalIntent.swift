import AppIntents

/// What the alarm's Stop button runs.
///
/// AlarmKit takes a `LiveActivityIntent` for `stopIntent`, and a
/// `LiveActivityIntent` whose `openAppWhenRun` is true brings the containing
/// app forward — which is the only supported way an alarm can hand the user
/// somewhere. Without it, Stop silences the ring and leaves them on the lock
/// screen, one step further from the page than before it went off.
///
/// It also posts `dawnBlockHandoff`, which is the same signal the shield's
/// "Write it now" notification sends in reminder mode — so being summoned by a
/// ringing alarm and being summoned by a shielded phone put the user in front
/// of the same card, selected the same way, with the same nudge. The two modes
/// differ in how they get your attention, and should differ in nothing after
/// that.
///
/// A cold launch is already covered by `HomeView.onAppear`; this is what makes
/// the warm case — app open on another tab when the alarm rings — behave the
/// same as the shield's.
struct OpenJournalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open JournalBlock"
    static let description = IntentDescription("Opens JournalBlock at today's page.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .dawnBlockHandoff, object: nil)
        return .result()
    }
}
