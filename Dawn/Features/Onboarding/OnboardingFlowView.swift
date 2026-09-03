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
        case analysing
        case plan
        case proof
        case commit
    }

    /// The full running order. Single definition — `init` reads it too, and
    /// two copies would drift the moment a step is added.
    static let order: [Step] = [.name]
        + QuizQuestion.allCases.map(Step.question)
        + [.wakeTime, .analysing, .plan, .proof, .commit]

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
                        QuizCard(question: question, answers: $answers) { advance() }
                    case .wakeTime:
                        WakeTimeCard(hour: $answers.wakeHour, minute: $answers.wakeMinute)
                    case .analysing:
                        AnalysingCard(answers: answers) { advance() }
                    case .plan:
                        PlanCard(plan: MorningPlan.make(from: answers))
                    case .proof:
                        ProofCard()
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
                Button {
                    Haptics.tap(.light)
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
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

                if case let .question(question) = step, question.allowsMultiple, !canAdvance {
                    Text("Pick at least one.")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .transition(.opacity)
                }
            }
            .animation(Theme.Motion.quick, value: canAdvance)
            .pageGutter()
            .padding(.bottom, Theme.Space.md)
        }
    }

    /// Hidden on single-choice questions (which auto-advance) and on the
    /// commit card (which has its own press-and-hold).
    private var showsContinue: Bool {
        switch step {
        case .commit: false
        case let .question(question): question.allowsMultiple
        default: true
        }
    }

    private var continueTitle: String {
        switch step {
        case .plan: "Looks right"
        case .proof: "Continue"
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
        prefs.hasCompletedQuiz = true
        prefs.hasOnboarded = true

        // Install the page the answers earned. The old version trimmed a
        // fixed set to a minute budget, which is why a ten-minute user was
        // promised five questions and given three — the set only had three.
        store.install(PromptPlan.make(from: answers))

        Haptics.success()
    }
}
