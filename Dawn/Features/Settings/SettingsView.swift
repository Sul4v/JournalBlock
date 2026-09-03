import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(ShieldService.self) private var shield
    @Environment(AuthController.self) private var auth
    @Environment(SubscriptionController.self) private var subs
    @Environment(BackupController.self) private var backup
    @State private var alarms = AlarmService.shared
    @State private var showAppPicker = false
    @State private var path: [Route]

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
                        accountSection
                        backupSection
                        ritualSection(prefs: prefs)
                        gateSection(prefs: prefs)
                        promptsSection
                        feelSection(prefs: prefs)
                        Color.clear.frame(height: Theme.Space.xxl)
                    }
                    .pageGutter()
                    .padding(.top, Theme.Space.sm)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .prompts: PromptLibraryView()
                case .account: AccountView()
                case .backup: BackupView()
                }
            }
            .familyActivityPicker(isPresented: $showAppPicker, selection: shieldSelection)
            .task { shield.refreshAuthorization() }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(AppConfig.appName).eyebrowStyle()
            Text("Settings")
                .font(Theme.Typography.serif(34))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shieldSelection: Binding<FamilyActivitySelection> {
        Binding(get: { shield.selection }, set: { shield.selection = $0 })
    }

    // MARK: - Sections

    private func ritualSection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return Group {
            SectionHeading(eyebrow: "The ritual", title: "Morning")

            GlassCard {
                VStack(spacing: Theme.Space.md) {
                    DatePicker(
                        "Journal time",
                        selection: Binding(
                            get: { prefs.wakeDate() },
                            set: { newValue in
                                let parts = Calendar.current.dateComponents(
                                    [.hour, .minute], from: newValue
                                )
                                prefs.wakeHour = parts.hour ?? 7
                                prefs.wakeMinute = parts.minute ?? 0
                                if prefs.alarmEnabled { rescheduleAlarm() }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .font(Theme.Typography.sans(16))
                    .foregroundStyle(Theme.Palette.ink)

                    Divider().overlay(Theme.Palette.rule)

                    SettingToggle(
                        title: "Wake alarm",
                        detail: alarms.isAuthorized
                            ? "Rings through silent mode and Focus."
                            : "Needs alarm permission.",
                        isOn: Binding(
                            get: { prefs.alarmEnabled },
                            set: { on in
                                prefs.alarmEnabled = on
                                on ? rescheduleAlarm() : alarms.cancelWakeAlarm()
                            }
                        )
                    )

                    Divider().overlay(Theme.Palette.rule)

                    SettingToggle(
                        title: "Evening reflection",
                        detail: "Optional second set of prompts, never gated.",
                        isOn: $prefs.eveningPromptsEnabled
                    )

                    if let error = alarms.lastError {
                        NoteLine(text: error)
                    }
                }
            }
        }
    }

    private func gateSection(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return Group {
            SectionHeading(eyebrow: "The lock", title: "Gate")

            GlassCard {
                VStack(spacing: Theme.Space.md) {
                    SettingToggle(
                        title: "Strict mode",
                        detail: "No way past the morning page. This is the point of Dawn.",
                        isOn: $prefs.strictMode
                    )

                    Divider().overlay(Theme.Palette.rule)

                    SettingToggle(
                        title: "Block other apps",
                        detail: "Shields your chosen apps until the page is written.",
                        isOn: Binding(
                            get: { prefs.blockAppsUntilDone },
                            set: { on in
                                prefs.blockAppsUntilDone = on
                                if on {
                                    Task { await shield.requestAuthorization() }
                                } else {
                                    shield.setShieldActive(false)
                                }
                            }
                        )
                    )

                    if prefs.blockAppsUntilDone {
                        Divider().overlay(Theme.Palette.rule)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apps to block")
                                    .font(Theme.Typography.sans(16))
                                    .foregroundStyle(Theme.Palette.ink)
                                Text(shield.hasSelection
                                     ? "\(shield.selection.applicationTokens.count) apps, \(shield.selection.categoryTokens.count) categories"
                                     : "Nothing chosen yet")
                                    .font(Theme.Typography.sans(12))
                                    .foregroundStyle(Theme.Palette.inkTertiary)
                            }
                            Spacer()
                            GhostButton(title: "Choose", isNested: true) { showAppPicker = true }
                        }

                        if let error = shield.lastError {
                            NoteLine(text: error)
                        }
                    }
                }
            }
        }
    }

    private var accountSection: some View {
        Group {
            SectionHeading(eyebrow: "You", title: "Account")

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
            SectionHeading(eyebrow: "Safekeeping", title: "Backup")

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
            SectionHeading(eyebrow: "Your questions", title: "Prompts")

            NavigationLink(value: Route.prompts) {
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit prompts")
                                .font(Theme.Typography.sans(16))
                                .foregroundStyle(Theme.Palette.ink)
                            Text("Reword, reorder, or write your own.")
                                .font(Theme.Typography.sans(12))
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
            SectionHeading(eyebrow: "Details", title: "Feel")

            GlassCard {
                VStack(spacing: Theme.Space.md) {
                    AppearancePicker(selection: $prefs.appearance)
                    Divider().overlay(Theme.Palette.rule)
                    // The label and the field were separate views, so
                    // VoiceOver announced the field as "Optional".
                    LabeledContent {
                        TextField("Name", text: $prefs.displayName, prompt: Text("Optional"))
                            .font(Theme.Typography.sans(16))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .tint(Theme.Palette.ember)
                            .accessibilityLabel("Name")
                    } label: {
                        Text("Name")
                            .font(Theme.Typography.sans(16))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
        }
    }

    private func rescheduleAlarm() {
        Task {
            await alarms.scheduleWakeAlarm(hour: prefs.wakeHour, minute: prefs.wakeMinute)
        }
    }
}

// MARK: - Rows

/// Light, dark, or follow the phone.
///
/// Three states rather than a switch: a switch has nowhere to put "follow the
/// system", so the first tap would strand the user on a fixed appearance
/// forever — and following the phone is where most people should stay. The
/// selection slides between segments rather than blinking, which is the one bit
/// of motion in Settings and the reason it reads as a physical control.
private struct AppearancePicker: View {
    @Binding var selection: Theme.Appearance

    /// Drives the sliding indicator. One capsule moves between segments instead
    /// of three capsules fading in and out.
    @Namespace private var indicator

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

            HStack(spacing: 0) {
                ForEach(Theme.Appearance.allCases) { option in
                    segment(option)
                }
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(Theme.Palette.ink.opacity(0.05)))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.Palette.rule, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Appearance")
            .accessibilityHint(detail)
        }
    }

    private var detail: String {
        switch selection {
        case .system: "Following your phone."
        case .light: "Warm paper, all day."
        case .dark: "Warm charcoal, easier at 6am."
        }
    }

    private func segment(_ option: Theme.Appearance) -> some View {
        let isSelected = selection == option
        return Button {
            guard !isSelected else { return }
            Haptics.tap(.light)
            withAnimation(Theme.Motion.settle) { selection = option }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.symbol)
                    .font(Theme.Typography.sans(12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(Theme.Typography.sans(14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            // Cream on near-black in light, charcoal on near-white in dark:
            // 13:1 either way, because both ends of the pair invert together.
            .foregroundStyle(isSelected ? Theme.Palette.canvas : Theme.Palette.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 40)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.ink.opacity(0.92))
                        .matchedGeometryEffect(id: "appearance.selection", in: indicator)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
