import SwiftUI
import FamilyControls

/// The one screen between the paywall and the app.
///
/// Three system dialogs in a row is the most hostile thing an app can do on
/// arrival, so this asks in the order the feature actually needs them and says
/// what each one buys before iOS puts up its own dialog:
///
///   1. Notifications — load-bearing. The shield's "Write it now" button
///      cannot open this app directly (see `ShieldActionHandler`); it posts a
///      notification and the user taps it. Without this permission that button
///      can only bounce them to the home screen.
///      2. Screen Time — the shield. It is followed by the app picker, and
///      that picker is not optional in any meaningful sense: the shield is
///      built from its tokens, so skipping it leaves reminder mode reporting
///      itself on and shutting nothing. See `GateSelection`.
///   3. Alarm — the wake alarm, which rings through silent mode and Focus.
///
/// Nothing here is mandatory. Every step is skippable and declining any of
/// them leaves a working app with an in-app gate; a paywall followed by a wall
/// of permissions the user cannot get past is both a bad first minute and a
/// reliable App Review rejection.
struct PermissionsPrimerView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(ShieldService.self) private var shield
    @Environment(\.journalStore) private var store

    var onFinish: () -> Void

    @State private var notifications: Step = .idle
    @State private var screenTime: Step = .idle
    @State private var alarm: Step = .idle
    @State private var isWorking = false
    @State private var appeared = false

    /// The apps the gate shuts, and the same tokens iOS meters so the shield
    /// can land on someone already inside one. See `GateSelection`.
    /// `includeEntireCategory: true` so a category pick yields real
    /// application tokens. See `SettingsView.reachSelection` for why that is
    /// the difference between a shield and nothing at all.
    @State private var reachSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var isPickingReach = false

    private enum Step: Equatable {
        case idle, granted, declined

        var symbol: String? {
            switch self {
            case .idle: nil
            case .granted: "checkmark"
            case .declined: "minus"
            }
        }
    }

    /// True once every request has been answered one way or the other.
    private var isSettled: Bool {
        notifications != .idle && screenTime != .idle && alarm != .idle
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    rows
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            }
            .safeAreaInset(edge: .bottom) { actions }
        }
        .familyActivityPicker(isPresented: $isPickingReach, selection: $reachSelection)
        .onChange(of: reachSelection) { _, new in
            GateBridge.selectionData = try? JSONEncoder().encode(new)
        }
        .onAppear {
            withAnimation(Theme.Motion.gentle) { appeared = true }
        }
        .task {
            if let data = GateBridge.selectionData,
               let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
               !(saved.applicationTokens.isEmpty && !saved.categoryTokens.isEmpty) {
                reachSelection = saved
            }
            // Someone who granted these on another device, or who is arriving
            // back here after a reinstall, shouldn't be asked again.
            await ReminderService.shared.refreshAuthorization()
            if ReminderService.shared.isAuthorized { notifications = .granted }
            shield.refreshAuthorization()
            if shield.isAuthorized { screenTime = .granted }
            if AlarmService.shared.isAuthorized { alarm = .granted }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Three permissions")
                .font(Theme.Typography.display(30))
                .foregroundStyle(Theme.Palette.ink)

            Text("This is what makes the block a block. You can change any of it later in Settings.")
                .font(Theme.Typography.sans(16))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: Theme.Space.sm) {
            row(
                symbol: "bell.badge",
                title: "Notifications",
                detail: "Nudges at each sitting — and the way back into the app when a blocked one is in front of you.",
                state: notifications
            )

            row(
                symbol: "hourglass",
                title: "Screen Time",
                detail: "Lets JournalBlock hold the apps you choose shut until the page is written.",
                state: screenTime,
                accessory: screenTime == .granted ? AnyView(reachRow) : nil
            )

            row(
                symbol: "alarm",
                title: "Alarm",
                detail: "Rings through silent mode and Focus at the sitting you asked to be woken for.",
                state: alarm
            )
        }
    }

    /// Offered under Screen Time once it is granted, and only there: it is a
    /// refinement of that permission, not a fourth thing to agree to. Naming
    /// the apps here is also the one chance to catch someone mid-scroll — see
    /// `requestAll`.
    private var reachRow: some View {
        Button {
            Haptics.tap(.light)
            isPickingReach = true
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(isReachEmpty
                     ? "Choose what gets shut. Nothing is blocked until you do."
                     : "\(reachCount) chosen. These stay shut until the page is written.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.emberDeep)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reachCount: Int {
        reachSelection.applicationTokens.count
            + reachSelection.categoryTokens.count
            + reachSelection.webDomainTokens.count
    }

    private func row(
        symbol: String,
        title: String,
        detail: String,
        state: Step,
        accessory: AnyView? = nil
    ) -> some View {
        GlassCard(tint: state == .granted
                  ? Theme.Palette.emberSoft.opacity(0.28)
                  : Theme.Palette.ink.opacity(0.04)) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    Image(systemName: symbol)
                        .font(Theme.Typography.sans(18, weight: .regular))
                        .foregroundStyle(Theme.Palette.ember)
                        .frame(width: 26)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Theme.Typography.sans(17, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(detail)
                            .font(Theme.Typography.sans(14))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Space.xs)

                    if let mark = state.symbol {
                        Image(systemName: mark)
                            .font(Theme.Typography.sans(13, weight: .semibold))
                            .foregroundStyle(state == .granted
                                             ? Theme.Palette.emberDeep
                                             : Theme.Palette.inkTertiary)
                    }
                }

                if let accessory { accessory }
            }
        }
        .animation(Theme.Motion.quick, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(accessibilityValue(for: state))
    }

    private func accessibilityValue(for state: Step) -> String {
        switch state {
        case .idle: "Not yet asked"
        case .granted: "Allowed"
        case .declined: "Not allowed"
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            EmberButton(
                title: isSettled ? "Done" : "Allow these",
                isEnabled: !isWorking
            ) {
                if isSettled {
                    finish()
                } else {
                    Task { await requestAll() }
                }
            }

            if !isSettled {
                GhostButton(title: "Not now") { finish() }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.sm)
        .background(.ultraThinMaterial)
    }

    /// Sequential, never concurrent: iOS shows one permission dialog at a time
    /// and firing all three at once drops two of them on the floor.
    private func requestAll() async {
        isWorking = true
        defer { isWorking = false }

        if notifications == .idle {
            let granted = await ReminderService.shared.requestAuthorization()
            withAnimation(Theme.Motion.quick) { notifications = granted ? .granted : .declined }
        }

        if screenTime == .idle {
            await shield.requestAuthorization()
            let granted = shield.isAuthorized
            withAnimation(Theme.Motion.quick) { screenTime = granted ? .granted : .declined }

        }

        if alarm == .idle {
            let granted = await AlarmService.shared.requestAuthorization()
            withAnimation(Theme.Motion.quick) { alarm = granted ? .granted : .declined }
        }

        // Last, and only once the three system dialogs are done with — a sheet
        // presented between them swallows the ones behind it.
        //
        // This is the step SleepBlock has and this app didn't, and skipping it
        // is why reminder mode shielded nothing for so long. An
        // `ApplicationToken` exists nowhere outside this picker, so with no
        // selection there is nothing to hand `ManagedSettings` and nothing for
        // `DeviceActivity` to meter.
        if screenTime == .granted, isReachEmpty {
            isPickingReach = true
        }
    }

    private var isReachEmpty: Bool {
        reachSelection.applicationTokens.isEmpty
            && reachSelection.categoryTokens.isEmpty
            && reachSelection.webDomainTokens.isEmpty
    }

    private func finish() {
        prefs.hasPrimedPermissions = true
        // Arm everything the user just agreed to, in one place, so a decline
        // on any one of them can't leave the others half-configured.
        let blocks = store.blocks()
        // Only the blocks with something to ask can ring.
        let ringable = store.activeBlocks()
        let owed = store.unwrittenBlockIDs()
        Task { await ReminderService.shared.reschedule(for: blocks) }
        Task {
            await AlarmService.shared.reschedule(
                for: ringable,
                enabled: prefs.gateMode == .alarm,
                owed: owed
            )
        }
        GateScheduler.reschedule(for: blocks, enabled: prefs.blockAppsUntilDone)
        onFinish()
    }
}
