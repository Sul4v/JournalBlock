import SwiftUI
import SwiftData

/// The writing experience. One card at a time, nothing else on screen.
struct JournalSessionView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var prefs
    @Environment(BackupController.self) private var backup

    @State private var session: JournalSession
    @FocusState private var focusedLine: Int?
    @Namespace private var glass

    /// Morning sessions inside the gate can't be escaped; evening ones can.
    let isDismissable: Bool
    var onFinish: () -> Void

    init(
        session: JournalSession,
        isDismissable: Bool,
        onFinish: @escaping () -> Void
    ) {
        _session = State(initialValue: session)
        self.isDismissable = isDismissable
        self.onFinish = onFinish
    }

    private var phase: DayPhase { DayPhase.current() }

    var body: some View {
        ZStack {
            SkyBackground(phase: phase, intensity: 1.0)

            VStack(spacing: 0) {
                header

                Group {
                    switch session.step {
                    case .mood:
                        MoodCard(mood: $session.mood)
                            .transition(cardTransition)
                    case let .prompt(index):
                        PromptCard(
                            prompt: session.prompts[index],
                            lines: $session.drafts[index],
                            focusedLine: $focusedLine
                        )
                        .id(index)
                        .transition(cardTransition)
                    case .complete:
                        CompletionCard(
                            session: session.session,
                            streak: store.currentStreak(assumingTodayComplete: true),
                            name: prefs.displayName
                        )
                        .transition(cardTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(Theme.Motion.settle, value: session.step)

                footer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Haptics.prepare() }
        .onChange(of: session.step) { _, newValue in
            // Land the caret on the first empty line of the new card.
            if case let .prompt(index) = newValue {
                let firstEmpty = session.drafts[index].firstIndex { $0.trimmed.isEmpty } ?? 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedLine = firstEmpty
                }
            } else {
                focusedLine = nil
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                if session.canGoBack {
                    IconButton(
                        systemName: "chevron.left",
                        accessibilityTitle: "Back"
                    ) {
                        session.goBack()
                    }
                    .transition(.opacity)
                }

                Spacer()

                Text(session.stepLabel)
                    .eyebrowStyle()

                Spacer()

                if isDismissable {
                    IconButton(
                        systemName: "xmark",
                        accessibilityTitle: "Close",
                        size: 13
                    ) {
                        dismiss()
                    }
                } else {
                    Color.clear.frame(width: Theme.Space.tapTarget, height: Theme.Space.tapTarget)
                }
            }
            .animation(Theme.Motion.quick, value: session.canGoBack)

            ProgressRule(progress: session.progress)
        }
        .pageGutter()
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.lg)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            if case .complete = session.step {
                EmberButton(title: "Start the day", systemImage: "arrow.up.right") {
                    finish()
                }
            } else {
                EmberButton(
                    title: session.isLastPrompt ? "Finish" : "Continue",
                    systemImage: session.isLastPrompt ? "checkmark" : nil,
                    isEnabled: session.canAdvance
                ) {
                    focusedLine = nil
                    let wasLast = session.isLastPrompt
                    session.advance()
                    // Their words hit disk here, not on the next tap.
                    if wasLast { persist() }
                }

                if case .prompt = session.step, !session.canAdvance {
                    Text("Write something — anything — to move on.")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .transition(.opacity)
                }
            }
        }
        .animation(Theme.Motion.quick, value: session.canAdvance)
        .pageGutter()
        .padding(.bottom, Theme.Space.md)
    }

    private var cardTransition: AnyTransition {
        Theme.Motion.slide(insertion: 22, removal: -16)
    }

    // MARK: - Actions

    /// Saves the writing without lifting the gate.
    private func persist() {
        store.record(
            session: session.session,
            answers: session.payload,
            mood: session.mood,
            markComplete: false
        )
        Haptics.success()
    }

    /// Acknowledges the completion card: this is what opens the day.
    private func finish() {
        store.markComplete(session: session.session)
        session.markComplete()
        onFinish()
        // Fire-and-forget on purpose. The writing is already safe on disk, so
        // a failed upload is worth a retry later, never a blocked morning.
        Task { try? await backup.sync(store: store) }
    }
}

// MARK: - Mood card

private struct MoodCard: View {
    @Binding var mood: Int?

    private var selected: Mood? { mood.flatMap(Mood.init(rawValue:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Before anything else")
                    .eyebrowStyle()
                Text("How are you arriving?")
                    .font(Theme.Typography.serif(34))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Space.md) {
                // Icons only: five words across a phone width either clip or
                // shrink to illegibility. The chosen one names itself below.
                GlassEffectContainer(spacing: 14) {
                    HStack(spacing: 10) {
                        ForEach(Mood.allCases) { option in
                            MoodChip(
                                option: option,
                                isSelected: mood == option.rawValue
                            ) {
                                Haptics.tap()
                                withAnimation(Theme.Motion.settle) { mood = option.rawValue }
                            }
                        }
                    }
                }

                Text(selected?.label ?? "Pick the one that fits")
                    .font(Theme.Typography.sans(14, weight: selected == nil ? .regular : .medium))
                    .foregroundStyle(selected == nil ? Theme.Palette.inkTertiary : Theme.Palette.ember)
                    .contentTransition(.opacity)
                    .animation(Theme.Motion.quick, value: mood)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .pageGutter()
        .padding(.top, Theme.Space.md)
    }
}

private struct MoodChip: View {
    let option: Mood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: option.symbol)
                .font(.system(size: 22, weight: isSelected ? .regular : .light))
                .foregroundStyle(isSelected ? Theme.Palette.emberDeep : Theme.Palette.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Space.tapTarget)
                .padding(.vertical, 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .glassEffect(
            .regular
                .tint(isSelected ? Theme.Palette.ember.opacity(0.20) : Theme.Palette.emberSoft.opacity(0.10))
                .interactive(),
            in: .rect(cornerRadius: 20)
        )
        .overlay {
            // Selection has to survive being read without colour.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? Theme.Palette.emberDeep : .clear, lineWidth: 2)
        }
        .scaleEffect(isSelected ? 1 + 0.06 * Theme.Motion.rise : 1)
        .animation(Theme.Motion.settle, value: isSelected)
    }
}

// MARK: - Prompt card

private struct PromptCard: View {
    let prompt: JournalPrompt
    @Binding var lines: [String]
    @FocusState.Binding var focusedLine: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(prompt.title)
                        .font(Theme.Typography.serif(32))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if !prompt.hint.isEmpty {
                        Text(prompt.hint)
                            .font(Theme.Typography.sans(14))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: Theme.Space.md) {
                    ForEach(lines.indices, id: \.self) { index in
                        WritingLine(
                            placeholder: placeholder(for: index),
                            text: $lines[index],
                            index: index,
                            accessibilityTitle: lines.count == 1
                                ? prompt.title
                                : "\(prompt.title), line \(index + 1) of \(lines.count)",
                            // An open answer gets a box with room in it
                            // before a word is typed. Both styles are one
                            // growing field underneath, so without this an
                            // open prompt and a one-line prompt look identical
                            // on arrival — and the page quietly asks for a
                            // sentence when it meant a paragraph.
                            minHeight: openAnswerHeight,
                            focused: $focusedLine
                        )
                    }
                }
            }
            .pageGutter()
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .onAppear {
            // Covers entry points that don't pass through a step change,
            // e.g. opening the evening session straight onto its first prompt.
            guard focusedLine == nil else { return }
            let firstEmpty = lines.firstIndex { $0.trimmed.isEmpty } ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                focusedLine = firstEmpty
            }
        }
    }

    private func placeholder(for index: Int) -> String {
        lines.count == 1 ? "…" : "\(index + 1)."
    }

    /// Nil for ruled lines, which size themselves to their text.
    private var openAnswerHeight: CGFloat? {
        prompt.style == .freeform ? 132 : nil
    }
}

// MARK: - Completion card

private struct CompletionCard: View {
    let session: JournalPrompt.Session
    let streak: Int
    let name: String

    @State private var revealed = false
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize = Theme.Display.numeral

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer(minLength: Theme.Space.lg)

            Image(systemName: session == .morning ? "sun.horizon.fill" : "moon.stars.fill")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Palette.gold, Theme.Palette.ember],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .scaleEffect(revealed ? 1 : 1 - 0.3 * Theme.Motion.rise)
                .opacity(revealed ? 1 : 0)

            VStack(spacing: Theme.Space.sm) {
                Text(session == .morning ? "That's the page turned." : "Today is closed.")
                    .font(Theme.Typography.serif(30))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)

                Text(session == .morning
                     ? "Your phone is yours again\(name.isEmpty ? "" : ", \(name)")."
                     : "Rest well.")
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 12 * Theme.Motion.rise)

            if streak > 0 {
                GlassCard(padding: Theme.Space.md) {
                    HStack(spacing: Theme.Space.md) {
                        Text("\(streak)")
                            .font(.system(size: numeralSize, weight: .light, design: .rounded))
                            .foregroundStyle(Theme.Palette.ember)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(streak == 1 ? "day" : "days in a row")
                                .font(Theme.Typography.sans(15, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                            Text("Keep the thread going.")
                                .font(Theme.Typography.sans(13))
                                .foregroundStyle(Theme.Palette.inkTertiary)
                        }
                        Spacer()
                    }
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 16 * Theme.Motion.rise)
            }

            Spacer(minLength: 0)
        }
        .pageGutter()
        .onAppear {
            withAnimation(Theme.Motion.gentle.delay(0.1)) { revealed = true }
        }
    }
}
