import SwiftUI

/// The long, personal on-ramp. Order matters: the user invests in describing
/// their own problem, sees it reflected back, commits out loud, and only then
/// is asked for an account. Every step before the account is answerable in one
/// tap, so the momentum never breaks.
struct OnboardingFlowView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.journalStore) private var store

    @State private var step: Step
    @State private var answers = QuizAnswers()
    /// The evening sitting's time. Not on `QuizAnswers` because nothing after
    /// onboarding reads it — it goes straight onto the block, which owns it
    /// from then on. The morning's time stays on the answers, where the alarm
    /// and the plan screen already read it.
    ///
    /// Seeded from the bedtime answer in `advance()`; these values only stand
    /// for a debug launch that skips that step.
    @State private var eveningHour = 22
    @State private var eveningMinute = 0
    @FocusState private var nameFocused: Bool

    /// Called when back is pressed on the very first step. Nil means the quiz
    /// is the root and there is nowhere behind it.
    var onExit: (() -> Void)?

    init(onExit: (() -> Void)? = nil) {
        self.onExit = onExit
        #if DEBUG
        let start = DebugHarness.onboardingStep
        #else
        let start: Int? = nil
        #endif
        let order = Self.order
        _step = State(initialValue: order[min(max(start ?? 0, 0), order.count - 1)])
    }

    enum Step: Hashable {
        case name
        case question(QuizQuestion)
        case wakeTime
        case bedTime
        /// One per sitting, morning then evening.
        case block(JournalPrompt.Session)
        case analysing
        case plan
        case commit
    }

    /// The full running order. Single definition — `init` reads it too, and
    /// two copies would drift the moment a step is added.
    /// The sittings come *after* the plan: the plan is the pitch, and asking
    /// someone to set two times before they have seen what they are setting
    /// them for is admin in the middle of a sales flow. "Looks right" now
    /// leads straight into filling the plan in.
    static let order: [Step] = [.name]
        + QuizQuestion.allCases.map(Step.question)
        + [.wakeTime, .bedTime, .analysing, .plan,
           .block(.morning), .block(.evening), .commit]

    private var sequence: [Step] { Self.order }

    private var index: Int { sequence.firstIndex(of: step) ?? 0 }

    /// The hook doesn't count — a progress bar that starts above zero on the
    /// first screen reads as dishonest.
    private var progress: Double {
        guard sequence.count > 1 else { return 0 }
        return Double(index) / Double(sequence.count - 1)
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: .sunrise)

            VStack(spacing: 0) {
                header

                Group {
                    switch step {
                    case .name:
                        NameCard(name: $answers.name, focused: $nameFocused)
                    case let .question(question):
                        QuizCard(question: question, answers: $answers)
                    case .block(.morning):
                        BlockSetupCard(
                            session: .morning,
                            hour: $answers.wakeHour,
                            minute: $answers.wakeMinute
                        )
                    case .block(.evening):
                        BlockSetupCard(
                            session: .evening,
                            hour: $eveningHour,
                            minute: $eveningMinute
                        )
                    case .wakeTime:
                        SleepTimeCard(
                            title: "When do you usually wake up?",
                            blurb: "Your morning page starts here, and so does the alarm.",
                            hour: $answers.wakeHour,
                            minute: $answers.wakeMinute
                        )
                    case .bedTime:
                        SleepTimeCard(
                            title: "And when do you go to bed?",
                            blurb: "The evening page lands half an hour before.",
                            hour: $answers.bedHour,
                            minute: $answers.bedMinute
                        )
                    case .analysing:
                        AnalysingCard(answers: answers) { advance() }
                    case .plan:
                        PlanCard(plan: MorningPlan.make(from: answers))
                    case .commit:
                        CommitCard(name: answers.name) { finish() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(Theme.Motion.settle, value: step)

                footer
            }
        }
        .onChange(of: step) { _, newValue in
            nameFocused = (newValue == .name)
        }
        .onAppear { Haptics.prepare() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            if canGoBack {
                // The shared control rather than a local button: it carries
                // the round shape, the tap haptic, and the 44pt target this
                // one was short of.
                IconButton(systemName: "chevron.left", accessibilityTitle: "Back") {
                    goBack()
                }
                .transition(.opacity)
            }

            ProgressRule(progress: progress)
        }
        .animation(Theme.Motion.quick, value: canGoBack)
        .pageGutter()
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.lg)
    }

    @ViewBuilder
    private var footer: some View {
        // The analysing card drives itself; a button there would be a lie.
        if step != .analysing {
            VStack(spacing: Theme.Space.sm) {
                // Continue is disabled until the question is answered, so
                // say why rather than leaving a dead button on screen. Sits
                // above the button: the eye is travelling down to the button,
                // and the reason should arrive before it, not after.
                //
                // Held in the layout and faded rather than inserted and
                // removed. The card above centres itself in whatever height
                // the footer leaves it, so a line appearing here nudges the
                // whole question.
                if case let .question(question) = step {
                    Text(question.allowsMultiple ? "Pick at least one." : "Pick one.")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .opacity(canAdvance ? 0 : 1)
                        .accessibilityHidden(canAdvance)
                }

                if showsContinue {
                    EmberButton(
                        title: continueTitle,
                        systemImage: nil,
                        isEnabled: canAdvance
                    ) {
                        nameFocused = false
                        advance()
                    }
                }
            }
            .animation(Theme.Motion.quick, value: canAdvance)
            .pageGutter()
            .padding(.bottom, Theme.Space.md)
        }
    }

    /// Hidden only on the commit card, which has its own press-and-hold.
    /// Every question gets a Continue press — tapping an option selects it and
    /// nothing more, so a mis-tap costs a correction rather than a screen.
    private var showsContinue: Bool {
        step != .commit
    }

    private var continueTitle: String {
        switch step {
        case .plan: "Looks right"
        default: "Continue"
        }
    }

    // MARK: - Rules

    private var canGoBack: Bool {
        guard step != .analysing else { return false }
        // Backing out of the first step means leaving the quiz, not moving
        // within it — only offered when there's something behind us.
        return index > 0 || onExit != nil
    }

    private var canAdvance: Bool {
        switch step {
        case let .question(question): answers.isAnswered(question)
        // The name is genuinely optional — blocking on it costs more users
        // than the personalisation is worth.
        default: true
        }
    }

    // MARK: - Navigation

    private func advance() {
        // Leaving the bedtime question re-seeds the evening sitting. Doing it
        // here rather than at the sitting screen means stepping back to change
        // your bedtime moves the page with it, which is what someone changing
        // that answer means.
        if step == .bedTime {
            let suggestion = answers.suggestedEveningTime
            eveningHour = suggestion.hour
            eveningMinute = suggestion.minute
        }
        guard index + 1 < sequence.count else { return finish() }
        withAnimation(Theme.Motion.settle) { step = sequence[index + 1] }
        Haptics.tap(.light)
    }

    private func goBack() {
        guard index > 0 else {
            onExit?()
            return
        }
        withAnimation(Theme.Motion.settle) { step = sequence[index - 1] }
    }

    private func finish() {
        answers.committed = true
        prefs.quizAnswers = answers
        prefs.displayName = answers.name.trimmed
        prefs.wakeHour = answers.wakeHour
        prefs.wakeMinute = answers.wakeMinute
        prefs.firstMorningSchedule.beginSignup()
        prefs.hasCompletedQuiz = true
        prefs.hasOnboarded = true

        // The same five questions for everyone, in the two sittings they just
        // set the times for. The old version picked a template from the quiz
        // and trimmed it to a minute budget, which is how a ten-minute user
        // was promised five questions and handed three.
        store.installStartingPage(
            morningHour: answers.wakeHour,
            morningMinute: answers.wakeMinute,
            eveningHour: eveningHour,
            eveningMinute: eveningMinute
        )

        // Both blocks want a reminder, but scheduling them is deliberately not
        // done here: it asks for notification permission, and the next screen
        // is the account form. A system dialog landing on top of "Save your
        // morning plan" competes with the one thing that screen is for.
        // `RootView` arms them when the user actually reaches the app.

        Haptics.success()
    }
}
