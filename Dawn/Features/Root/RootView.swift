import SwiftUI
import SwiftData

/// The gate chain. Each stage must clear before the next is even rendered:
///
///   quiz → account → subscription → tomorrow's prompts in the app
///
/// Order is deliberate. The quiz comes first so the user has invested before
/// being asked for anything; the account comes before the paywall so a purchase
/// has somewhere to attach.
///
/// Clearing the chain lands on Today, always. An unanswered block is shown
/// there as something owed, not imposed as a screen the user has to write their
/// way out of.
struct RootView: View {
    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs
    @Environment(ShieldService.self) private var shield
    @Environment(AuthController.self) private var auth
    @Environment(SubscriptionController.self) private var subs
    @Environment(BackupController.self) private var backup
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
    /// Not read directly — held so that editing a block in Settings (moving its
    /// time, handing it the lock, deleting it) re-evaluates the gate at once.
    @Query private var blocks: [JournalBlock]

    @State private var today = Calendar.current.startOfDay(for: .now)
    /// Ticks every minute so a block that becomes due while the app is open
    /// closes the gate then, rather than at the next launch.
    @State private var clock = Date.now

    /// Which door the user picked on the welcome screen. Ephemeral on purpose —
    /// relaunching before finishing puts them back at the choice.
    @State private var entry: Entry = .undecided

    private enum Entry { case undecided, newUser, returningUser }

    /// Set when the user leaves the welcome screen with the quiz already
    /// behind them. That's the only case where the account screen has a
    /// welcome screen to go back to — during first run the quiz sits between
    /// the two, and stepping back into it isn't what the chevron means.
    @State private var welcomeIsBehind = false

    /// Bumped to rebuild the account form when "Create one" has no quiz to
    /// restart. See `startSignUp`.
    @State private var accountFormEpoch = 0

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

    /// The block the user owes right now, if any. Nil means the phone is theirs.
    ///
    /// This no longer chooses what to render — Today is always what renders.
    /// It feeds `syncShield`, so the Screen Time shield still lifts and falls
    /// with the owed block.
    ///
    /// `entries` and `blocks` are both read here rather than only inside the
    /// store, so that finishing a session or handing the lock to another block
    /// re-runs this at once instead of at the next launch.
    private var pendingGateBlock: JournalBlock? {
        guard !isBeforeFirstSession else { return nil }
        return store.pendingGateBlock(
            at: clock,
            blocks: blocks,
            entry: entries.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
        )
    }

    private var owesGatedWriting: Bool { pendingGateBlock != nil }

    /// Which of today's blocks are written, as a value `onChange` can compare.
    ///
    /// Writing a page in the app cancels its own chain directly, from
    /// `JournalStore.stamp`. This is what catches the other way a block gets
    /// written: pulled down from backup, where a page finished on an iPad turns
    /// up here as a changed entry and nothing else. Without it the alarm would
    /// go on ringing for a page that is demonstrably done.
    private var writtenTodayFingerprint: String {
        let entry = entries.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
        return blocks
            .filter { entry?.isComplete($0.id) == true }
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
    }

    /// Shows the tomorrow preview in place of the ordinary Today screen. Fresh
    /// signups only.
    private var isPreparingFirstMorning: Bool {
        prefs.firstMorningSchedule.isPreparing(for: auth.user?.id, on: today)
    }

    /// Holds the shield off until this account's first session day, however they
    /// arrived. Someone signing in gets today to look around before the phone
    /// starts asking anything of them.
    private var isBeforeFirstSession: Bool {
        prefs.firstMorningSchedule.isBeforeFirstSession(for: auth.user?.id, on: today)
    }

    /// Offered at `.app` and not before, so it can never appear over the quiz,
    /// the auth flow, or the paywall — by which point Today is on screen, which
    /// is where a returning user with an old journal lands.
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
        .animation(Theme.Motion.gentle, value: owesGatedWriting)
        .sheet(isPresented: $isOfferingUnlock) {
            UnlockBackupSheet()
        }
        // Both, because the two can settle in either order: the status may
        // resolve while the paywall is still up, or the user may clear the last
        // gate after backup has already reported itself locked.
        .onChange(of: backup.status) { _, _ in offerUnlockIfNeeded() }
        .onChange(of: stage, initial: true) { _, newStage in
            if newStage == .app, let user = auth.user {
                prefs.firstMorningSchedule.beginAccess(for: user.id)
                // Arms the block reminders a new signup asked for. Here rather
                // than at the end of the quiz because this call asks for
                // notification permission, and reaching the app is the first
                // moment that dialog isn't sitting on top of the account form
                // or the paywall.
                let blocks = store.blocks()
                Task { await ReminderService.shared.reschedule(for: blocks) }
            }
            offerUnlockIfNeeded()
        }
        .task {
            await auth.restore()
            #if DEBUG
            await DebugHarness.signInDemoAccount(auth: auth, subs: subs)
            #endif
            await subs.bind(to: auth.user)
        }
        .onChange(of: auth.state) { _, newState in
            if let user = newState.user {
                prefs.hasEverSignedIn = true
                prefs.firstMorningSchedule.bind(to: user.id)
            }
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
                // Leaving without writing is exactly the case the chain exists
                // for: the user pressed Stop, landed here, and walked away. Top
                // it up on the way out so the next hour of rings is queued.
                refreshAlarms()
                return
            }
            guard phase == .active else { return }
            clock = .now
            // The key may have arrived from iCloud Keychain since we last
            // looked, which silently clears a lock nobody needed to see.
            backup.recheckKey()
            // Crossing midnight while backgrounded must re-arm the gate.
            today = Calendar.current.startOfDay(for: .now)
            syncShield()
            // Subscriptions can lapse or be cancelled outside the app.
            Task { await subs.refreshStatus() }
            // Re-arm block reminders: an edit made on another device arrives
            // through backup, not through this screen.
            //
            // Only once the user is actually in the app. Rescheduling asks for
            // notification permission when it has something to schedule, and
            // blocks exist on the device from the moment the quiz finishes —
            // so without this guard the system prompt fired on every launch,
            // including the welcome screen, before the user had signed up or
            // paid, for reminders they had not yet agreed to.
            if stage == .app {
                let blocks = store.blocks()
                Task { await ReminderService.shared.reschedule(for: blocks) }
                // The monitor windows are what re-apply the shield on a phone
                // that sat untouched overnight. Rebuilt here because a block
                // edited on another device arrives through backup, not a view.
                GateScheduler.reschedule(for: blocks, enabled: prefs.blockAppsUntilDone)
                // Tops the alarm chain back up for every block that still owes
                // a page. The Stop button on an alarm opens the app, so this is
                // the moment a silenced ring becomes the next one — which is
                // what makes writing the page the only way to end them.
                refreshAlarms()
            }
        }
        .onChange(of: owesGatedWriting) { _, _ in syncShield() }
        .onChange(of: writtenTodayFingerprint) { _, _ in refreshAlarms() }
        // Switching into reminder mode has to raise the shield on a block that
        // is already owed. Without this the mode changes and nothing happens
        // until the next time the owed state moves — which, for a block due
        // this morning, is tomorrow.
        .onChange(of: prefs.gateMode) { _, _ in
            syncShield()
            // And silences the alarms on the way out of alarm mode, or arms
            // them on the way in. Neither happens on its own.
            refreshAlarms()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Calendar.current.startOfDay(for: .now)
            clock = .now
            syncShield()
            // Yesterday's chain belongs to yesterday. This is what puts today's
            // alarms on a phone that was left open across midnight.
            refreshAlarms()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            clock = now
        }
    }

    private func leaveWelcome(as door: Entry) {
        welcomeIsBehind = prefs.hasCompletedQuiz
        withAnimation(Theme.Motion.gentle) { entry = door }
    }

    /// Both entrances to the sign-up flow: "Get started" on the welcome screen
    /// and "Create one" on the sign-in screen.
    ///
    /// Whether that means *redoing the quiz* turns on one thing: is there a
    /// plan on this phone that no account has claimed yet.
    ///
    /// If there is, the person looking at it built it minutes ago and is
    /// bouncing between the two doors on the account screen — making them
    /// re-answer fourteen screens to get back to the form they were just
    /// looking at is absurd. If there isn't, a new account is a different
    /// person, and they answer the quiz themselves rather than inheriting the
    /// plan built for whoever signed out.
    ///
    /// This used to ask `hasEverSignedIn` instead, which is a fact about the
    /// *device*, not about the plan: anyone who had ever signed in on this
    /// phone — which is everyone, after the first time — got the quiz again.
    private func startSignUp() {
        welcomeIsBehind = false

        guard !prefs.firstMorningSchedule.isAwaitingAccount else {
            // The form's sign-in/sign-up mode is init-only state, so nothing
            // below would move it back on its own — the quiz restart used to
            // reset it as a side effect of tearing the screen down.
            accountFormEpoch += 1
            withAnimation(Theme.Motion.gentle) { entry = .newUser }
            return
        }

        prefs.restartQuiz()
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
        case permissions
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
        guard subs.isSubscribed else { return .paywall }
        // The permissions the feature runs on, asked once, after the purchase.
        // Before it, and they're being asked to hand over Screen Time by an app
        // they haven't decided to keep.
        return prefs.hasPrimedPermissions ? .app : .permissions
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
                onGetStarted: { startSignUp() },
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
            .id(accountFormEpoch)
            .transition(.opacity)
        case .paywall:
            PaywallView()
                .transition(.opacity)
        case .permissions:
            // No `onExit`: this screen is skippable by its own "Not now", and
            // there is nothing behind it to go back to.
            PermissionsPrimerView(onFinish: {})
                .transition(.opacity)
        case .app:
            // The app never opens onto the writing flow, however much is owed.
            // A block still to be answered is announced on Today, next to the
            // block itself, and the user starts it when they choose. The owed
            // state still drives `syncShield` below, so the Screen Time promise
            // is unchanged — what went away is being made to write on entry.
            MainTabView(isPreparingFirstMorning: isPreparingFirstMorning)
                .transition(.opacity)
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
        case .permissions: PermissionsPrimerView(onFinish: { debugScreen = .home })
        case .account: MainTabView(start: .settings, settingsRoute: .account)
        case .gate: MorningGateView()
        case .journal: MorningGateView(startWriting: true)
        case .writing: MorningGateView(startWriting: true, startAt: .prompt(0))
        case .complete: MorningGateView(startWriting: true, startAt: .complete)
        case .home: MainTabView(start: .today)
        case .tomorrow: MainTabView(isPreparingFirstMorning: true)
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

    /// Keeps the system-wide Screen Time shield in step with the in-app gate,
    /// and mirrors the owed block into the app group so the shield extension
    /// can name it. The mirror is written even when no shield is applied: the
    /// extension may be launched moments after the app is gone, and stale copy
    /// on a shield is worse than none.
    private func syncShield() {
        guard prefs.hasCompletedQuiz else { return }
        shield.sync(
            pending: pendingGateBlock.map(mirrored),
            blockingEnabled: prefs.blockAppsUntilDone
        )
    }

    /// Keeps the alarm chain in step with what the day still owes.
    ///
    /// Idempotent and silent — it schedules only what's missing and never asks
    /// for permission — so it can be called from every moment that might have
    /// changed the answer without costing anything when nothing did.
    private func refreshAlarms() {
        guard prefs.hasCompletedQuiz else { return }
        // Only the blocks with something to ask can ring, which is the same
        // list `unwrittenBlockIDs` narrows to.
        let ringable = store.activeBlocks()
        let owed = store.unwrittenBlockIDs(on: clock)
        let enabled = prefs.alarmEnabled
        Task {
            await AlarmService.shared.refresh(for: ringable, enabled: enabled, owed: owed)
        }
    }

    /// The few facts a shield can show, flattened out of SwiftData.
    private func mirrored(_ block: JournalBlock) -> GateBridge.PendingBlock {
        GateBridge.PendingBlock(
            id: block.id,
            title: block.title,
            timeLabel: block.timeLabel,
            promptCount: store.prompts(for: block).count,
            minutesOfDay: block.minutesOfDay,
            symbolName: block.icon
        )
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
