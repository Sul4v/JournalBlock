import SwiftUI
import SwiftData

/// The writing experience: the whole sitting on one page.
///
/// It used to deal the prompts out one card at a time, with a progress rule and
/// a Continue between each. That reads well the first morning and badly the
/// hundredth — you cannot see what you already wrote, you cannot go back to
/// change a word without walking the stack, and a four-question block is four
/// screens of ceremony for four sentences. A page shows the questions and the
/// answers together, scrolls, and finishes once.
struct JournalSessionView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var prefs
    @Environment(BackupController.self) private var backup

    @State private var session: JournalSession
    @FocusState private var focusedLine: Field?
    @Namespace private var glass

    /// A session inside the gate can't be escaped; every other one can.
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

    /// One writing field on the page. The prompt has to be part of it: a line
    /// index alone names a field in every question at once.
    private struct Field: Hashable {
        let prompt: Int
        let line: Int
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: phase, intensity: 1.0)

            VStack(spacing: 0) {
                Group {
                    if case .complete = session.step {
                        CompletionCard(
                            block: session.block,
                            streak: store.currentStreak(assumingTodayComplete: true),
                            name: prefs.displayName
                        )
                        .transition(cardTransition)
                    } else {
                        page
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(Theme.Motion.settle, value: session.step)

                footer
            }
        }
        // Floated rather than stacked. As a row of its own the close button
        // reserved 44pt plus its padding above the page, which put the title a
        // long way down a screen that has nothing else at the top. Over the
        // content it costs no height at all, and the page's soft top edge
        // keeps text from colliding with it on the way past.
        .overlay(alignment: .topTrailing) { closeButton }
        // The button belongs to the screen, not to the keyboard. Riding up on
        // top of the keyboard it covered the line being typed and left Finish
        // sitting in the middle of the page — a control the user isn't ready
        // for, in the way of the one they are.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Haptics.prepare() }
        // Whatever was typed survives leaving the page, finished or not. The
        // card flow only ever wrote on the last Continue, so backing out of
        // question three lost questions one and two.
        .onDisappear { persistIfWritten() }
    }

    // MARK: - The page

    private var page: some View {
        ScrollView {
            // Deliberately the same shape as `EntryDetailView`: the sitting
            // named in serif at the top, then question-and-answer pairs down
            // the page. Writing a page and reading one back should not be two
            // different documents.
            //
            // A title, not an eyebrow. The header above carries only the way
            // out, so an ember tick of a label left the page opening on a
            // small grey question with nothing above it.
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(session.block.timeLabel)
                    .font(Theme.Typography.serif(30))
                    .foregroundStyle(Theme.Palette.ink)

                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(session.prompts.indices, id: \.self) { index in
                        promptSection(index)
                    }
                }
            }
            .pageGutter()
            .padding(.top, Theme.Space.sm)
            // Deep enough that the last line can always be scrolled clear of
            // the keyboard, which no longer shortens the page for us.
            .padding(.bottom, 320)
            // Tapping the paper puts the keyboard away, the way setting a pen
            // down does. With `scrollDismissesKeyboard` above it that makes two
            // ways out — needed, because the keyboard covers Finish and a
            // `ToolbarItemGroup(placement: .keyboard)` renders nothing from a
            // `fullScreenCover`, with or without a `NavigationStack` around it.
            .contentShape(Rectangle())
            .onTapGesture { focusedLine = nil }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .softTopEdge()
    }

    private func promptSection(_ index: Int) -> some View {
        let prompt = session.prompts[index]

        return VStack(alignment: .leading, spacing: 8) {
            // Small, grey, and above the writing — the same label History puts
            // over the answers it shows back. It was 24pt serif here, which
            // made the question the loudest thing on a page whose whole point
            // is what you write under it.
            Text(prompt.title)
                .font(Theme.Typography.sans(12, weight: .medium))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if !prompt.hint.isEmpty {
                Text(prompt.hint)
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Space.sm) {
                ForEach(session.drafts[index].indices, id: \.self) { line in
                    WritingLine(
                        placeholder: placeholder(index, line),
                        text: $session.drafts[index][line],
                        field: Field(prompt: index, line: line),
                        accessibilityTitle: session.drafts[index].count == 1
                            ? prompt.title
                            : "\(prompt.title), line \(line + 1) of \(session.drafts[index].count)",
                        // An open answer gets a box with room in it before a
                        // word is typed. Both styles are one growing field
                        // underneath, so without this an open prompt and a
                        // one-line prompt look identical on arrival.
                        minHeight: prompt.style == .freeform ? 132 : nil,
                        focused: $focusedLine
                    )
                }
            }
            .padding(.top, 2)
        }
        .padding(.bottom, Theme.Space.xs)
    }

    private func placeholder(_ prompt: Int, _ line: Int) -> String {
        session.drafts[prompt].count == 1 ? "…" : "\(line + 1)."
    }

    /// Every question needs a line, which is the rule the card flow enforced by
    /// refusing to advance. A gate that lifts on one sentence out of four is a
    /// gate with a hole in it.
    private var canFinish: Bool {
        !session.prompts.isEmpty
            && session.prompts.indices.allSatisfy(session.isAnswered)
    }

    // MARK: - Chrome

    @ViewBuilder
    private var closeButton: some View {
        if isDismissable {
            IconButton(
                systemName: "xmark",
                accessibilityTitle: "Close",
                size: 12
            ) {
                dismiss()
            }
            .padding(.trailing, Theme.Space.gutter)
            .padding(.top, Theme.Space.sm)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            if case .complete = session.step {
                EmberButton(title: finishTitle, systemImage: "arrow.up.right") {
                    finish()
                }
            } else {
                // Above the button, and held in the layout rather than
                // inserted, so the page doesn't shift as it comes and goes.
                Text("Every question needs a line — anything — to finish.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .opacity(canFinish ? 0 : 1)
                    .accessibilityHidden(canFinish)

                EmberButton(
                    title: "Finish",
                    systemImage: "checkmark",
                    isEnabled: canFinish
                ) {
                    focusedLine = nil
                    persist()
                    withAnimation(Theme.Motion.settle) { session.step = .complete }
                }
            }
        }
        .animation(Theme.Motion.quick, value: canFinish)
        .pageGutter()
        .padding(.bottom, Theme.Space.md)
    }

    /// "Start the day" is what unlocking the phone feels like, and nothing
    /// else. A 10pm reflection ending on it read like the app had lost track
    /// of what time it was.
    private var finishTitle: String {
        if session.block.gatesDay { return "Start the day" }
        return session.block.hour >= 17 || session.block.hour < 5 ? "Good night" : "Done"
    }

    private var cardTransition: AnyTransition {
        Theme.Motion.slide(insertion: 22, removal: -16)
    }

    // MARK: - Actions

    /// Saves whatever is on the page if any of it was written. Called on the
    /// way out as well as on Finish, so closing the sheet mid-page keeps the
    /// lines rather than dropping them.
    private func persistIfWritten() {
        guard session.prompts.indices.contains(where: session.isAnswered) else { return }
        store.record(
            block: session.block,
            answers: session.payload,
            markComplete: false
        )
    }

    /// Saves the writing without lifting the gate.
    private func persist() {
        store.record(
            block: session.block,
            answers: session.payload,
            markComplete: false
        )
        Haptics.success()
    }

    /// Acknowledges the completion card: this is what opens the day.
    private func finish() {
        store.markComplete(block: session.block)
        session.markComplete()
        onFinish()
        // Fire-and-forget on purpose. The writing is already safe on disk, so
        // a failed upload is worth a retry later, never a blocked morning.
        Task { try? await backup.sync(store: store) }
    }
}

// MARK: - Completion card

private struct CompletionCard: View {
    let block: JournalBlock
    let streak: Int
    let name: String

    @State private var revealed = false
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize = Theme.Display.numeral

    /// The words fit the block, not the clock: the sentence that matters after
    /// a gated session is that the phone is unlocked, whatever hour it is.
    private var headline: String {
        if block.gatesDay { return "That's the page turned." }
        return block.hour >= 17 || block.hour < 4 ? "Today is closed." : "That's it for now."
    }

    private var subhead: String {
        if block.gatesDay {
            return "Your phone is yours again\(name.isEmpty ? "" : ", \(name)")."
        }
        return block.hour >= 17 || block.hour < 4 ? "Rest well." : "Back to it."
    }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer(minLength: Theme.Space.lg)

            Image(systemName: block.icon + ".fill")
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
                Text(headline)
                    .font(Theme.Typography.serif(30))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)

                Text(subhead)
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
