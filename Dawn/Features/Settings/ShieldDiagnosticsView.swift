#if DEBUG
import SwiftUI
import DeviceActivity
import FamilyControls

/// Everything the gate decided, and everything it wrote down, on one screen.
///
/// The Screen Time chain runs across four processes and the only one with a
/// console anyone can watch is the app. When a block's hour goes by with no
/// shield there is otherwise no way to tell these apart:
///
///   - the monitor extension never ran
///   - it ran and resolved nothing owed
///   - it ran, resolved a block, and the shield was applied to a store nothing
///     was reading
///   - Family Controls was never authorized in the first place
///
/// All four look identical from the outside — an unshielded phone — and every
/// one of them has cost a day of guessing at some point. `GateBridge` has been
/// writing a `MonitorTrace` on every callback for exactly this, and until now
/// nothing read it back.
///
/// DEBUG only. It is reached from the bottom of Settings rather than a launch
/// argument because the answers only exist on a real device, hours after the
/// build, with the phone off the cable.
struct ShieldDiagnosticsView: View {
    @Environment(ShieldService.self) private var shield
    @Environment(Preferences.self) private var prefs

    @State private var now = Date.now

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    verdict
                    manual
                    picked
                    inputs
                    mirror
                    windows
                    trace
                    Color.clear.frame(height: Theme.Space.xxl)
                }
                .pageGutter()
                .padding(.top, Theme.Space.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Shield diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - Would a shield be up right now, and if not, which link is broken

    /// The first failing precondition, in the order they actually gate each
    /// other. Naming one cause beats listing five green ticks and one red.
    private var blocker: String? {
        if prefs.gateMode != .reminder {
            return "Gate mode is \(prefs.gateMode.label). Only Reminder shields."
        }
        if !shield.isAuthorized {
            return "Family Controls is \(authorizationLabel). Nothing can be shielded."
        }
        if GateSelection.isEmpty {
            return "No apps chosen. The shield is built from picker tokens, so an empty selection shields nothing. Open \"Apps to shut\"."
        }
        if GateSelection.shieldsNothing {
            return "Categories chosen but no apps behind them. A category policy alone does not shield — re-open \"Apps to shut\" and pick again."
        }
        if !GateBridge.isShieldingEnabled {
            return "The app group says shielding is off. The app has not synced since the mode changed."
        }
        guard let schedule = GateBridge.schedule else {
            return "No schedule in the app group. The app has never synced — check that RootView reached stage .app."
        }
        if schedule.blocks.isEmpty {
            return "The mirrored schedule is empty. No block both gates the day and has prompts."
        }
        if GateBridge.pendingBlock(now: now) == nil {
            return "Every gating block is written for today, so nothing is owed."
        }
        return nil
    }

    private var verdict: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(blocker == nil ? "A shield should be up" : "No shield")
                    .font(Theme.Typography.serif(24))
                    .foregroundStyle(Theme.Palette.ink)
                Text(blocker ?? "Open any non-Apple app and the gate screen should appear.")
                    .font(Theme.Typography.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if blocker == nil, !shield.isShieldActive {
                    Text("This process believes it has not applied one. The monitor extension may still have.")
                        .font(Theme.Typography.sans(12))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var inputs: some View {
        section("Inputs") {
            field("Gate mode", prefs.gateMode.label)
            field("Family Controls", authorizationLabel)
            field("Shielding enabled", GateBridge.isShieldingEnabled ? "yes" : "no")
            field("App applied a shield", shield.isShieldActive ? "yes" : "no")
            field("Store", "default (unnamed)")
            field("App group", GateBridge.appGroup)
            if let error = shield.lastError {
                field("Last error", error)
            }
        }
    }

    private var mirror: some View {
        section("Mirrored schedule") {
            if let schedule = GateBridge.schedule {
                field("Written day", Self.day.string(from: schedule.writtenDay))
                field("Gating blocks", "\(schedule.blocks.count)")
                field("Written today", "\(schedule.written.count)")
                ForEach(schedule.blocks, id: \.id) { block in
                    field(
                        block.timeLabel,
                        schedule.written.contains(block.id)
                            ? "\(block.title) · written"
                            : "\(block.title) · owed"
                    )
                }
                field("Owed now", GateBridge.pendingBlock(now: now)?.timeLabel ?? "nothing")
            } else {
                field("Schedule", "absent")
            }
        }
    }

    /// The picked apps, drawn by the system from their tokens.
    ///
    /// `Label(ApplicationToken)` is the only way to find out what a token
    /// actually refers to: they are opaque, deliberately unreadable, and
    /// nothing in the app group says "Instagram". Which means a selection can
    /// look perfect in every count we log and still be pointing at the wrong
    /// app — a possibility no amount of reading the code can rule out.
    private var picked: some View {
        section("What is shielded") {
            let selection = GateSelection.current
            if selection.applicationTokens.isEmpty {
                field("Apps", "none")
            } else {
                ForEach(Array(selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .labelStyle(.titleAndIcon)
                        .font(Theme.Typography.sans(14))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(Array(selection.categoryTokens), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(Theme.Typography.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Applies and clears the shield by hand, from the app, which is the one
    /// process known to hold approved authorization.
    ///
    /// Everything else here waits on a schedule, a block coming due, and an
    /// extension the system launches when it feels like it. This takes all of
    /// that out of the picture: tap, then open Instagram. If the shield appears
    /// the mechanism works and the fault is in what triggers it. If it doesn't,
    /// the fault is in the shield itself and no amount of scheduling will help.
    private var manual: some View {
        section("Force it") {
            Button {
                Haptics.tap(.light)
                shield.setShieldActive(true)
                now = .now
            } label: {
                Text("Shield now")
                    .font(Theme.Typography.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.emberDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap(.light)
                shield.setShieldActive(false)
                now = .now
            } label: {
                Text("Lift it")
                    .font(Theme.Typography.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var windows: some View {
        section("Registered windows") {
            let activities = DeviceActivityCenter().activities
            if activities.isEmpty {
                field("Activities", "none — GateScheduler has registered nothing")
            } else {
                ForEach(activities.map(\.rawValue).sorted(), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            field("App tokens", "\(GateSelection.current.applicationTokens.count)")
            field("Category tokens", "\(GateSelection.current.categoryTokens.count)")
            field("Web tokens", "\(GateSelection.current.webDomainTokens.count)")
        }
    }

    /// The monitor's own account of itself, newest first — the only evidence
    /// that the extension is being launched at all.
    private var trace: some View {
        section("Monitor callbacks") {
            let entries = GateBridge.monitorTrace.reversed()
            if entries.isEmpty {
                Text("Nothing recorded. The system has not launched the monitor extension since it was installed — or the extension is not embedded in the build on this phone.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Self.stamp.string(from: entry.at))  \(entry.event)  \(entry.shielded ? "shielded" : "cleared")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("\(entry.activity)  ·  \(entry.pending ?? "nothing owed")  ·  enabled: \(entry.enabled ? "yes" : "no")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Pieces

    private var authorizationLabel: String {
        switch shield.authorizationStatus {
        case .approved: "approved"
        case .denied: "denied"
        case .notDetermined: "not determined"
        @unknown default: "unknown"
        }
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: title)
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Text(name)
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.inkTertiary)
            Spacer(minLength: Theme.Space.sm)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm:ss"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}
#endif
