#if DEBUG
import Foundation
import SwiftData

/// Launch-argument hooks for QA and screenshots. DEBUG only — none of this
/// ships. Run the scheme with, for example:
///
///     -dawnScreen home -dawnSeedSampleData
///
enum DebugHarness {
    /// Forces RootView past the gate to a specific screen.
    enum Screen: String {
        case welcome, onboarding, auth, paywall, permissions, account
        case gate, journal, writing, complete
        case home, tomorrow, history, settings, prompts, backup
        /// The recovery-phrase hand-off, with a throwaway phrase. Reviewable
        /// on its own because in production it appears once per account.
        case recoveryPhrase, unlockBackup
        /// Why the gate did or didn't shield, and what the monitor extension
        /// recorded. Behind a launch argument rather than a Settings row: it
        /// answers a question nobody has while the app is working, and a
        /// stethoscope in the settings of a journal is furniture.
        case shieldDiagnostics
    }

    private static let args = ProcessInfo.processInfo.arguments

    static var forcedScreen: Screen? {
        guard let index = args.firstIndex(of: "-dawnScreen"),
              index + 1 < args.count else { return nil }
        return Screen(rawValue: args[index + 1])
    }

    static var wantsSampleData: Bool {
        args.contains("-dawnSeedSampleData")
    }

    /// Signs into a throwaway local account and grants entitlement, so the
    /// account and subscription screens can be reviewed without a real backend.
    static var wantsDemoAccount: Bool {
        args.contains("-dawnDemoAccount")
    }

    /// Holds the store in its loading state so skeletons and spinners can
    /// actually be looked at. RevenueCat caches offerings, so after the first
    /// fetch the real loading window is far too short to screenshot.
    static var wantsSlowStore: Bool {
        args.contains("-dawnSlowStore")
    }

    /// Opens the onboarding flow at a given index in its running order.
    static var onboardingStep: Int? {
        guard let index = args.firstIndex(of: "-dawnOnboardingStep"),
              index + 1 < args.count else { return nil }
        return Int(args[index + 1])
    }

    @MainActor
    static func signInDemoAccount(auth: AuthController, subs: SubscriptionController) async {
        guard wantsDemoAccount, !auth.isSignedIn else { return }
        let email = "demo@dawn.app"
        let password = "dawn-demo-password"
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            try? await auth.signUp(email: email, password: password, confirmation: password)
        }
        await subs.bind(to: auth.user)
        await subs.loadPlans()
        if let plan = subs.recommendedPlan, !subs.isSubscribed {
            _ = try? await subs.purchase(plan)
        }
    }

    /// Two weeks of plausible history including today, so history, streak,
    /// and the home recap all have something honest to render.
    @MainActor
    static func seedSampleData(into store: JournalStore) {
        guard wantsSampleData else { return }
        let calendar = Calendar.current
        guard let block = store.blocks().first(where: \.gatesDay) ?? store.blocks().first
        else { return }
        let prompts = store.prompts(for: block)
        guard !prompts.isEmpty else { return }

        let gratitude = [
            ["Coffee before anyone else was up", "A quiet inbox", "The walk home last night"],
            ["Rain on the window", "My sister called", "Finished the chapter"],
            ["Slept through the night", "Warm kitchen", "An easy commute"],
            ["Old friends who still text", "The smell of bread", "Nothing urgent today"]
        ]
        let great = [
            ["Ship the first draft", "Walk at lunch", "Cook instead of order"],
            ["One hard conversation", "Leave the desk by six", "Call Dad"],
            ["Deep work before noon", "Stretch", "Read twenty pages"],
            ["Say no to one thing", "Fix the sink", "Early night"]
        ]
        let affirmations = [
            ["I do the difficult thing first"],
            ["I am allowed to move slowly"],
            ["I finish what I start"],
            ["I am steady under pressure"]
        ]

        for offset in 0...14 {
            // A believable gap, so the streak logic is visibly exercised.
            if offset == 6 || offset == 11 { continue }
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let bucket = offset % 4
            let answers = zip(prompts, [gratitude[bucket], great[bucket], affirmations[bucket]])
                .map { (prompt: $0, lines: $1) }
            store.record(
                block: block,
                answers: Array(answers),
                on: date
            )
        }
    }
}
#endif
