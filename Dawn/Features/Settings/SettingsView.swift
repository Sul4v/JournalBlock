import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(ShieldService.self) private var shield
    @Environment(AuthController.self) private var auth
    @Environment(SubscriptionController.self) private var subs
    @Environment(BackupController.self) private var backup
    @Environment(\.journalStore) private var store
    @State private var alarms = AlarmService.shared
    private var reminders: ReminderService { ReminderService.shared }
    @State private var path: [Route]
    /// Which apps iOS should meter so the shield can land on someone already
    /// inside one. See `GateScheduler.reachEvent` — this never decides what is
    /// shielded, only where we can catch you.
    /// `includeEntireCategory: true` is load-bearing, not a detail.
    ///
    /// With the default initialiser, picking a category fills `categoryTokens`
    /// and leaves `applicationTokens` **empty** — and a category policy with no
    /// application tokens behind it shields nothing. That is the state this app
    /// shipped in: thirteen categories chosen, zero apps, `shield.applications`
    /// set to nil, and Instagram opening straight through. It is the same
    /// failure as the earlier `.all()` attempt, which is a category policy with
    /// no tokens by another route.
    ///
    /// With this flag the picker resolves a category down to the concrete apps
    /// inside it, so choosing Social hands us real `ApplicationToken`s.
    @State private var reachSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var isPickingReach = false

    /// Screens pushed on top of Settings.
    enum Route: Hashable { case prompts, account, backup }

    init(start: Route? = nil) {
        _path = State(initialValue: start.map { [$0] } ?? [])
    }

    var body: some View {
        @Bindable var prefs = prefs

        NavigationStack(path: $path) {
            ZStack {
                SkyBackground(phase: DayPhase.current(), intensity: 0.55)

                ScrollView {
                    VStack(spacing: Theme.Space.lg) {
                        masthead
                        // What you write, then what gets you to it, then
                        // where it's kept. Taste after that, and the plumbing
                        // behind all of it — permissions and account — last.
                        promptsSection
                        gateSection(prefs: prefs)
                        backupSection
                        feelSection(prefs: prefs)
                        permissionsSection
                        accountSection
                        Color.clear.frame(height: Theme.Space.xxl)
                    }
                    .pageGutter()
                    .padding(.top, Theme.Space.sm)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .softTopEdge()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .prompts: PromptLibraryView()
                case .account: AccountView()
                case .backup: BackupView()
                }
            }
            .task { shield.refreshAuthorization() }
        }
    }

    /// What is set up, in two short lines: how often, then when.
    ///
    /// It used to be one line carrying a count, the times and a separate
    /// sentence of explanation, under a heading that already said "Your
    /// Prompts" — three descriptions of the same thing stacked on top of
    /// each other.
    private var scheduleSummary: (rhythm: String, times: String) {
        let blocks = store.activeBlocks()
        guard !blocks.isEmpty else {
            return ("Not set up yet", "Choose what you answer, and when.")
        }
        let rhythm = blocks.count == 1 ? "Once a day" : "\(blocks.count) times a day"
        let shown = blocks.prefix(4).map(\.timeLabel).joined(separator: " · ")
        return (rhythm, blocks.count > 4 ? "\(shown) · …" : shown)
    }

    private var masthead: some View {
        Text("Settings")
            .font(Theme.Typography.serif(34))
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private func gateSection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return Group {
            SectionHeading(title: "Notification style")

            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    // Two rows rather than a segmented control, which is what
                    // this was. A segment shows one description at a time, so
                    // choosing meant flipping back and forth to compare — fine
                    // for Appearance, where the names say everything, and no
                    // use at all here, where the names are "Alarm" and
                    // "Reminder" and the difference is whether your phone gets
                    // taken away. Both consequences are on screen now.
                    ForEach(GateMode.allCases, id: \.self) { mode in
                        GateModeRow(
                            mode: mode,
                            isSelected: prefs.gateMode == mode
                        ) {
                            guard prefs.gateMode != mode else { return }
                            Haptics.tap(.light)
                            withAnimation(Theme.Motion.quick) { prefs.gateMode = mode }
                        }
                    }

                    if prefs.gateMode == .reminder {
                        Divider().overlay(Theme.Palette.rule)
                        Button {
                            Haptics.tap(.light)
                            isPickingReach = true
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Apps to shut")
                                        .font(Theme.Typography.sans(15, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.ink)
                                    Text(reachSummary)
                                        .font(Theme.Typography.sans(13))
                                        .foregroundStyle(Theme.Palette.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: Theme.Space.sm)
                                Image(systemName: "chevron.right")
                                    .font(Theme.Typography.sans(13, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.inkTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if let error = alarms.lastError, prefs.gateMode == .alarm {
                        NoteLine(text: error)
                    }
                    if let error = shield.lastError, prefs.gateMode == .reminder {
                        NoteLine(text: error)
                    }
                }
            }
            .familyActivityPicker(isPresented: $isPickingReach, selection: $reachSelection)
            .onChange(of: reachSelection) { _, new in
                GateBridge.selectionData = try? JSONEncoder().encode(new)
                GateScheduler.reschedule(
                    for: store.blocks(),
                    enabled: prefs.blockAppsUntilDone
                )
                // These tokens *are* the shield now, so a change here has to
                // reach the store at once. Before, picking apps during an owed
                // block left the phone open until the next foreground.
                shield.setShieldActive(
                    prefs.blockAppsUntilDone && GateBridge.pendingBlock() != nil
                )
            }
            .task {
                if let data = GateBridge.selectionData,
                   let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
                   // A selection saved before `includeEntireCategory` was set
                   // carries categories with no apps behind them, which shields
                   // nothing. Drop it rather than show it back as if it worked.
                   !(saved.applicationTokens.isEmpty && !saved.categoryTokens.isEmpty) {
                    reachSelection = saved
                }
                // An empty picker in reminder mode is the block silently doing
                // nothing, which is the exact failure this feature keeps
                // landing in. Ask once, here, rather than let it sit.
                if prefs.gateMode == .reminder, shield.isAuthorized, reachCount == 0 {
                    isPickingReach = true
                }
            }
            .onChange(of: prefs.gateMode) { _, _ in applyGateMode() }
        }
    }

    /// What the picker has, in words.
    ///
    /// The empty case has to read as an alarm, because it is one. These tokens
    /// are the whole shield — `.all()` shielded nothing on device, twice — so
    /// an empty picker is reminder mode switched off while reporting itself on.
    /// That state is also what `emptyReachWarning` and the auto-present in
    /// `body` exist to stop the user sitting in.
    ///
    /// The same tokens are what iOS meters, which is what lets the shield land
    /// on someone already inside an app. Picking whole *categories* rather than
    /// single apps is worth doing for that reason alone: it widens both the
    /// block and the catch in one tap.
    private var reachSummary: String {
        guard reachCount > 0 else {
            return "Nothing chosen, so nothing is shut. Pick the apps — or whole categories — you lose time in."
        }
        return "\(reachCount) chosen. These stay shut until the page is written."
    }

    private var reachCount: Int {
        reachSelection.applicationTokens.count
            + reachSelection.categoryTokens.count
            + reachSelection.webDomainTokens.count
    }

    /// Everything the mode implies, in one place, so switching can't leave the
    /// other half of the previous mode still armed.
    private func applyGateMode() {
        let blocks = store.blocks()
        // Only the blocks with something to ask can ring; an empty one has
        // nothing for the alarm to hold the user to.
        let ringable = store.activeBlocks()
        let owed = store.unwrittenBlockIDs()
        let mode = prefs.gateMode

        Task { await alarms.reschedule(for: ringable, enabled: mode == .alarm, owed: owed) }

        if mode == .reminder {
            Task {
                await shield.requestAuthorization()
                // Raise it here, not only in `RootView`. The root's own
                // `onChange(of: gateMode)` has already been and gone by the
                // time the system dialog is answered, and it read the service
                // as unauthorized — so switching mode on a block that is
                // already owed armed everything and shielded nothing until the
                // next foreground.
                // The mirror is already correct — the root wrote it
                // synchronously when the mode changed — so this only has to
                // apply what the mirror already says.
                shield.setShieldActive(
                    prefs.blockAppsUntilDone && GateBridge.pendingBlock() != nil
                )
            }
        } else {
            shield.setShieldActive(false)
        }
        GateScheduler.reschedule(for: blocks, enabled: mode == .reminder)
        Task { await ReminderService.shared.reschedule(for: blocks) }
    }

    private var permissionsSection: some View {
        Group {
            SectionHeading(title: "Permissions")

            GlassCard {
                VStack(spacing: Theme.Space.md) {
                    PermissionRow(
                        title: "Notifications",
                        detail: "How a block says it's due, and the shield's way back.",
                        isGranted: reminders.isAuthorized
                    ) {
                        let granted = await ReminderService.shared.requestAuthorization()
                        if granted {
                            await ReminderService.shared.reschedule(for: store.blocks())
                        }
                    }

                    Divider().overlay(Theme.Palette.rule)

                    PermissionRow(
                        title: "Screen Time",
                        detail: "Lets \(AppConfig.appName) shut the other apps.",
                        isGranted: shield.isAuthorized
                    ) {
                        await shield.requestAuthorization()
                    }

                    Divider().overlay(Theme.Palette.rule)

                    PermissionRow(
                        title: "Alarm",
                        detail: "Rings through silent mode and Focus.",
                        isGranted: alarms.isAuthorized
                    ) {
                        let granted = await AlarmService.shared.requestAuthorization()
                        if granted {
                            await alarms.reschedule(
                                for: store.activeBlocks(),
                                enabled: prefs.gateMode == .alarm,
                                owed: store.unwrittenBlockIDs()
                            )
                        }
                    }
                }
            }
        }
        .task { await ReminderService.shared.refreshAuthorization() }
    }

    private var accountSection: some View {
        Group {
            SectionHeading(title: "Account")

            NavigationLink(value: Route.account) {
                GlassCard {
                    HStack(spacing: Theme.Space.md) {
                        Text(auth.user?.initials ?? "\u{00B7}")
                            .font(Theme.Typography.sans(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.canvas)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.Palette.ink.opacity(0.85)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.user?.email ?? "Not signed in")
                                .font(Theme.Typography.sans(15, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(subs.isSubscribed ? "\(AppConfig.appName) \(AppConfig.tierName)" : "No subscription")
                                .font(Theme.Typography.sans(12))
                                .foregroundStyle(subs.isSubscribed ? Theme.Palette.ember : Theme.Palette.inkTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
    }

    private var backupSection: some View {
        Group {
            SectionHeading(title: "Backup")

            NavigationLink(value: Route.backup) {
                GlassCard {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: backupIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.Palette.emberDeep)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.Palette.emberSoft.opacity(0.4)))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(backupTitle)
                                .font(Theme.Typography.sans(15, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                            Text("Encrypted on this phone. We can't read it.")
                                .font(Theme.Typography.sans(12))
                                .foregroundStyle(Theme.Palette.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
    }

    private var backupIcon: String {
        switch backup.status {
        case .ready: "lock.shield.fill"
        case .locked: "lock.trianglebadge.exclamationmark"
        case .needsSetup, .unavailable: "lock.shield"
        }
    }

    private var backupTitle: String {
        switch backup.status {
        case .ready: "Backup is on"
        case .locked: "Backup needs unlocking"
        case .needsSetup: "Backup is off"
        case .unavailable: "Backup"
        }
    }

    private var promptsSection: some View {
        Group {
            SectionHeading(title: "Your Blocks")

            NavigationLink(value: Route.prompts) {
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scheduleSummary.rhythm)
                                .font(Theme.Typography.sans(16))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(scheduleSummary.times)
                                .font(Theme.Typography.sans(12))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.inkTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func feelSection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return Group {
            SectionHeading(title: "Feel")

            GlassCard {
                AppearancePicker(selection: $prefs.appearance)
            }
        }
    }

}

// MARK: - Rows

/// Light, dark, or follow the phone, using the system's Liquid Glass control.
private struct AppearancePicker: View {
    @Binding var selection: Theme.Appearance

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance")
                    .font(Theme.Typography.sans(16))
                    .foregroundStyle(Theme.Palette.ink)
                Text(detail)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHidden(true)

            Picker("Appearance", selection: $selection) {
                ForEach(Theme.Appearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .labelsHidden()
            .accessibilityHint(detail)
            .onChange(of: selection) { _, _ in
                Haptics.tap(.light)
            }
        }
    }

    private var detail: String {
        switch selection {
        case .system: "Following your phone."
        case .light: "Warm paper, all day."
        case .dark: "Warm charcoal, easier at 6am."
        }
    }
}

/// One of the two ways a block can ask for its page.
///
/// Deliberately not a `GlassCard` each: glass inside glass flattens the
/// hierarchy, so the selected row is marked with a plain tinted rectangle and
/// the card around them stays the only pane.
private struct GateModeRow: View {
    let mode: GateMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        isSelected ? Theme.Palette.emberDeep : Theme.Palette.inkTertiary
                    )
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.label)
                        .font(Theme.Typography.sans(16, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(mode.detail)
                        .font(Theme.Typography.sans(12))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Theme.Space.xs)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? Theme.Palette.emberDeep : Theme.Palette.inkTertiary
                    )
                    .padding(.top, 1)
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                    .fill(isSelected ? Theme.Palette.emberSoft.opacity(0.30) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One permission: what it buys, and a way to ask for it.
///
/// Never a toggle. iOS only lets an app ask once — after that the answer lives
/// in the system Settings app — so a switch here would be a control that
/// silently stops working, which is worse than a button that says "Allow".
private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () async -> Void

    @State private var isWorking = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sans(16))
                    .foregroundStyle(Theme.Palette.ink)
                Text(detail)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.xs)

            if isGranted {
                Image(systemName: "checkmark")
                    .font(Theme.Typography.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.emberDeep)
                    .padding(.top, 3)
            } else {
                GhostButton(title: "Allow", isNested: true) {
                    guard !isWorking else { return }
                    isWorking = true
                    Task {
                        await request()
                        isWorking = false
                    }
                }
            }
        }
        .animation(Theme.Motion.quick, value: isGranted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(isGranted ? "Allowed" : "Not allowed")
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sans(16))
                    .foregroundStyle(Theme.Palette.ink)
                Text(detail)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.Palette.ember)
    }
}

private struct NoteLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text(text)
                .font(Theme.Typography.sans(12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Palette.emberDeep)
        .accessibilityElement(children: .combine)
    }
}
