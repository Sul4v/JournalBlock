import SwiftUI
import SwiftData

/// The locked front door. No tab bar, no back gesture, no dismiss.
/// A moment of calm first, then straight into writing.
struct MorningGateView: View {
    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs

    @State private var isWriting: Bool
    @State private var appeared = false
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
            SkyBackground(phase: phase)

            if isWriting {
                JournalSessionView(
                    session: JournalSession(
                        session: .morning,
                        prompts: store.prompts(for: .morning),
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
            withAnimation(Theme.Motion.gentle.delay(0.15)) { appeared = true }
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Space.lg)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .eyebrowStyle()
                    .opacity(appeared ? 1 : 0)

                Text("\(phase.greeting)\(prefs.greetingName).")
                    .font(.system(size: greetingSize, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14 * Theme.Motion.rise)

                Text("A few lines before the day starts. Everything else can wait.")
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

            if !prefs.strictMode {
                // Only reachable when the user has deliberately turned strict
                // mode off in settings.
                HStack {
                    Spacer()
                    GhostButton(title: "Not this morning") {
                        store.record(session: .morning, answers: [], mood: nil)
                    }
                    Spacer()
                }
                .padding(.bottom, Theme.Space.xs)
            }
        }
        .pageGutter()
        .padding(.bottom, Theme.Space.md)
    }

    @ViewBuilder
    private var streakLine: some View {
        let streak = store.currentStreak()
        if streak > 0 {
            HStack(spacing: 8) {
                Image(systemName: "flame")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.ember)
                Text("\(streak) morning\(streak == 1 ? "" : "s") in a row")
                    .font(Theme.Typography.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }
}
