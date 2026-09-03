import SwiftUI
import SwiftData

/// The gate chain. Each stage must clear before the next is even rendered:
///
///   quiz → account → subscription → today's page → the app
///
/// Order is deliberate. The quiz comes first so the user has invested before
/// being asked for anything; the account comes before the paywall so a purchase
/// has somewhere to attach; the journal gate comes last because it's the only
/// one that repeats every day.
struct RootView: View {
    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs
    @Environment(ShieldService.self) private var shield
    @Environment(AuthController.self) private var auth
    @Environment(SubscriptionController.self) private var subs
    @Environment(BackupController.self) private var backup
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]

    @State private var today = Calendar.current.startOfDay(for: .now)

    /// Which door the user picked on the welcome screen. Ephemeral on purpose —
    /// relaunching before finishing puts them back at the choice.
    @State private var entry: Entry = .undecided

    private enum Entry { case undecided, newUser, returningUser }

    /// Set when the user leaves the welcome screen with the quiz already
    /// behind them. That's the only case where the account screen has a
    /// welcome screen to go back to — during first run the quiz sits between
    /// the two, and stepping back into it isn't what the chevron means.
    @State private var welcomeIsBehind = false

    /// A locked backup means this account has a journal on the server that this
    /// device can't read — almost always a reinstall or a new phone. Offer the
    /// phrase prompt once per launch rather than leaving it buried in Settings,
    /// where a returning user has no reason to look for it.
    @State private var hasOfferedUnlock = false
    @State private var isOfferingUnlock = false

    #if DEBUG
    /// Held in state, not read from the launch args each time, so the escape
    /// hatch below can clear it and drop back into the real flow.
    @State private var debugScreen: DebugHarness.Screen? = DebugHarness.forcedScreen
    #endif

    private var todaysEntry: JournalEntry? {
        entries.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
    }

    private var owesMorningPages: Bool {
        todaysEntry?.isMorningComplete != true
    }

    /// Offered at `.app` and not before, so it can never appear over the quiz,
    /// the auth flow, or the paywall. It *can* appear over the morning gate,
    /// which is deliberate: a fresh install has no entries, so the gate is
    /// exactly where a returning user lands, and making them write a page
    /// before mentioning their old journal would be perverse.
    private func offerUnlockIfNeeded() {
        guard stage == .app,
              backup.status == .locked,
              // Someone who just chose to forget the key doesn't want to be
              // asked, in the same breath, to type it back in.
              !backup.didDeliberatelyForget,
              !hasOfferedUnlock
        else { return }
        hasOfferedUnlock = true
        isOfferingUnlock = true
    }

    var body: some View {
        Group {
            #if DEBUG
            if let debugScreen {
                debugDestination(debugScreen)
                    .overlay(alignment: .topTrailing) { debugExit }
            } else {
                gatedContent
            }
            #else
            gatedContent
            #endif
        }
        .animation(Theme.Motion.gentle, value: stage)
        .animation(Theme.Motion.gentle, value: owesMorningPages)
        .sheet(isPresented: $isOfferingUnlock) {
            UnlockBackupSheet()
        }
        // Both, because the two can settle in either order: the status may
        // resolve while the paywall is still up, or the user may clear the last
        // gate after backup has already reported itself locked.
        .onChange(of: backup.status) { _, _ in offerUnlockIfNeeded() }
        .onChange(of: stage) { _, _ in offerUnlockIfNeeded() }
        .task {
            await auth.restore()
            #if DEBUG
            await DebugHarness.signInDemoAccount(auth: auth, subs: subs)
            #endif
            await subs.bind(to: auth.user)
        }
        .onChange(of: auth.state) { _, newState in
            if newState.isSignedIn { prefs.hasEverSignedIn = true }
            // Signing out puts the choice back in front of them. Guarded on
            // the quiz so this can't yank a first-run user out of the funnel
            // when the initial restore reports "signed out".
            if newState == .signedOut, prefs.hasCompletedQuiz { returnToWelcome() }
            Task { await subs.bind(to: auth.user) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Prompt and preference edits apply immediately and have no save
            // button, so there's no other moment that means "they're done".
            // Entries have their own trigger when a session finishes; this is
            // what gets settings changes off the device.
            if phase == .background {
                Task { try? await backup.sync(store: store) }
                return
            }
            guard phase == .active else { return }
            // The key may have arrived from iCloud Keychain since we last
            // looked, which silently clears a lock nobody needed to see.
            backup.recheckKey()
            // Crossing midnight while backgrounded must re-arm the gate.
            today = Calendar.current.startOfDay(for: .now)
            syncShield()
            // Subscriptions can lapse or be cancelled outside the app.
            Task { await subs.refreshStatus() }
        }
        .onChange(of: owesMorningPages) { _, _ in syncShield() }
    }

    private func leaveWelcome(as door: Entry) {
        welcomeIsBehind = prefs.hasCompletedQuiz
        withAnimation(Theme.Motion.gentle) { entry = door }
    }

    /// "Create one" from the sign-in screen. A second account on this phone is
    /// a different person, so they answer the quiz themselves rather than
    /// inheriting the plan built for whoever signed out.
    private func startSignUp() {
        prefs.restartQuiz()
        welcomeIsBehind = false
        withAnimation(Theme.Motion.gentle) { entry = .newUser }
    }

    private func returnToWelcome() {
        welcomeIsBehind = false
        withAnimation(Theme.Motion.gentle) { entry = .undecided }
    }

    // MARK: - Stages

    private enum Stage: Equatable {
        case holding
        case newPassword
        case welcome
        case quiz
        case account
        case paywall
        case app
    }

    private var stage: Stage {
        // A half-finished password reset outranks everything, including the
        // journal gate — the user came here to fix one specific thing.
        if auth.needsNewPassword { return .newPassword }

        if !prefs.hasCompletedQuiz {
            // Someone already signed in has done this before on another device;
            // don't make them re-answer the quiz to get back to their account.
            if auth.isSignedIn { return subscriptionStage }
            switch entry {
            case .undecided: return .welcome
            case .newUser: return .quiz
            case .returningUser: return .account
            }
        }
        switch auth.state {
        case .restoring: return .holding
        case .signedOut:
            // Signing out otherwise strands the user on the account screen
            // with nothing behind it. The quiz is done, so both doors on the
            // welcome screen lead straight to the account screen — the point
            // is having somewhere to step back to.
            return entry == .undecided ? .welcome : .account
        case .signedIn:
            return subscriptionStage
        }
    }

    /// Wait for a real answer rather than flashing the paywall at someone who
    /// has already paid.
    private var subscriptionStage: Stage {
        guard subs.hasResolvedStatus else { return .holding }
        return subs.isSubscribed ? .app : .paywall
    }

    @ViewBuilder
    private var gatedContent: some View {
        switch stage {
        case .holding:
            HoldingView()
                .transition(.opacity)
        case .newPassword:
            NewPasswordView()
                .transition(.opacity)
        case .welcome:
            WelcomeView(
                onGetStarted: { leaveWelcome(as: .newUser) },
                onSignIn: { leaveWelcome(as: .returningUser) }
            )
            .transition(.opacity)
        case .quiz:
            OnboardingFlowView(
                onExit: { withAnimation(Theme.Motion.gentle) { entry = .undecided } }
            )
            .transition(.opacity)
        case .account:
            AuthFlowView(
                // "Get started" means sign up even for someone who has an old
                // account on this install, so the door they picked outranks
                // whether they've ever signed in.
                returning: entry != .newUser && (prefs.hasEverSignedIn || entry == .returningUser),
                // Only offer a way back when the welcome screen is behind us.
                onBack: welcomeIsBehind || entry == .returningUser
                    ? { returnToWelcome() }
                    : nil,
                // Always routed through the root: "Create one" has to start the
                // sign-up journey, never retitle this form into it.
                onWantsSignUp: { startSignUp() }
            )
            .transition(.opacity)
        case .paywall:
            PaywallView()
                .transition(.opacity)
        case .app:
            if owesMorningPages {
                MorningGateView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
    }

    #if DEBUG
    /// Some debug screens are pushed views with no parent, so there is nothing
    /// to go back to. Without this, launching one strands the app until it's
    /// force-quit — which looks exactly like a bug in the app itself.
    private var debugExit: some View {
        Button {
            Haptics.tap(.light)
            withAnimation(Theme.Motion.settle) { debugScreen = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ladybug")
                Text("Exit debug")
            }
            .font(Theme.Typography.sans(11, weight: .semibold))
            .foregroundStyle(Theme.Palette.canvas)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
        }
        .background(Capsule().fill(Theme.Palette.ink.opacity(0.75)))
        .clipShape(Capsule())
        // Top-right: the bottom of most screens belongs to the primary
        // action, and a debug chip sitting on the CTA is worse than useless.
        .padding(.trailing, Theme.Space.sm)
        .padding(.top, 4)
    }

    /// Jumps straight to one screen for QA and screenshots.
    @ViewBuilder
    private func debugDestination(_ screen: DebugHarness.Screen) -> some View {
        switch screen {
        case .welcome:
            WelcomeView(
                onGetStarted: { debugScreen = .onboarding },
                onSignIn: { debugScreen = .auth }
            )
        case .onboarding:
            // Mirrors production, where the quiz always has the welcome screen
            // behind it — so the back chrome under test matches what ships.
            OnboardingFlowView(onExit: { debugScreen = .welcome })
        case .auth: AuthFlowView(returning: prefs.hasEverSignedIn)
        case .paywall: PaywallView()
        case .account: MainTabView(start: .settings, settingsRoute: .account)
        case .gate: MorningGateView()
        case .journal: MorningGateView(startWriting: true)
        case .writing: MorningGateView(startWriting: true, startAt: .prompt(0))
        case .complete: MorningGateView(startWriting: true, startAt: .complete)
        case .home: MainTabView(start: .today)
        case .history: MainTabView(start: .entries)
        case .settings: MainTabView(start: .settings)
        case .prompts: MainTabView(start: .settings, settingsRoute: .prompts)
        case .backup: MainTabView(start: .settings, settingsRoute: .backup)
        case .recoveryPhrase:
            RecoveryPhraseSheet(phrase: RecoveryPhrase.formatted(RecoveryPhrase.generate()))
        case .unlockBackup: UnlockBackupSheet()
        }
    }
    #endif

    /// Keeps the system-wide Screen Time shield in step with the in-app gate.
    private func syncShield() {
        guard prefs.hasCompletedQuiz else { return }
        shield.setShieldActive(prefs.blockAppsUntilDone && owesMorningPages)
    }
}

/// Shown while the session and entitlement are being restored. Deliberately
/// almost empty — a spinner-heavy splash makes a fast launch feel slow.
private struct HoldingView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size = Theme.Display.greeting

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current())
            Text(AppConfig.appName)
                .font(.system(size: size, weight: .regular, design: .serif))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading \(AppConfig.appName)")
    }
}
