import SwiftUI
import SwiftData

/// The locked front door. No tab bar, no back gesture, no dismiss.
/// A moment of calm first, then straight into writing.
///
/// Named for the morning because that is where it started, but it now stands
/// in front of any block that holds the lock — a new account locks the evening
/// sitting too — so everything it says is written off the block's own hour.
struct MorningGateView: View {
    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs

    @State private var isWriting: Bool
    @State private var appeared = false
    /// Resolved once, when the gate appears, and held.
    ///
    /// Read live it would go nil the moment the last prompt is marked complete,
    /// and the completion card — which is still on screen, waiting to be
    /// acknowledged — would be yanked back to the welcome panel.
    @State private var block: JournalBlock?
    @ScaledMetric(relativeTo: .largeTitle) private var greetingSize = Theme.Display.greeting

    /// `startAt` is only ever non-nil from the DEBUG QA harness.
    private let startAt: JournalSession.Step?

    init(startWriting: Bool = false, startAt: JournalSession.Step? = nil) {
        _isWriting = State(initialValue: startWriting)
        self.startAt = startAt
    }

    private var phase: DayPhase { DayPhase.current() }

    var body: some View {
        ZStack {
            if !isWriting {
                SkyBackground(phase: phase)
            }

            if isWriting, let block {
                JournalSessionView(
                    session: JournalSession(
                        block: block,
                        prompts: store.prompts(for: block),
                        existing: store.entry(),
                        startAt: startAt
                    ),
                    isDismissable: false,
                    onFinish: {
                        // The gate lifts on its own: RootView is watching the
                        // entry's completion date. Nothing to do here.
                    }
                )
                .transition(.opacity)
            } else {
                welcome
                    .transition(Theme.Motion.slide(insertion: 12, removal: -12))
            }
        }
        .animation(Theme.Motion.gentle, value: isWriting)
        .interactiveDismissDisabled(true)
        .onAppear {
            if block == nil {
                block = store.pendingGateBlock()
                    ?? store.blocks().first(where: \.gatesDay)
                    ?? store.activeBlocks().first
            }
            withAnimation(Theme.Motion.gentle.delay(0.15)) { appeared = true }
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Space.lg)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("\(phase.greeting)\(prefs.greetingName).")
                    .font(.system(size: greetingSize, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14 * Theme.Motion.rise)

                Text(invitation)
                    .font(Theme.Typography.sans(16))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18 * Theme.Motion.rise)
            }

            Spacer(minLength: Theme.Space.lg)
                .frame(maxHeight: 180)

            streakLine
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, Theme.Space.md)

            EmberButton(title: "Begin", systemImage: "arrow.right") {
                isWriting = true
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20 * Theme.Motion.rise)
            .padding(.bottom, Theme.Space.md)

        }
        .pageGutter()
        .padding(.bottom, Theme.Space.md)
    }

    /// The line under the greeting.
    ///
    /// Written off the *clock*, not the block's hour. A page can be owed hours
    /// after the hour it belongs to — a 7am block answered at three in the
    /// afternoon — and reading it off the block put "A few lines before the
    /// day starts" directly under "Good afternoon." The greeting is the time
    /// of day, so this has to be too, or the two contradict each other.
    private var invitation: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "A few lines before the day starts. Everything else can wait."
        case 11..<16: "A quiet minute in the middle of it. Everything else can wait."
        case 16..<20: "Take stock before the evening. Everything else can wait."
        default: "A few lines to close the day out. Everything else can wait."
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        let streak = store.currentStreak()
        if streak > 0 {
            HStack(spacing: 8) {
                Image(systemName: "flame")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.ember)
                Text("\(streak) day\(streak == 1 ? "" : "s") in a row")
                    .font(Theme.Typography.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }
}
