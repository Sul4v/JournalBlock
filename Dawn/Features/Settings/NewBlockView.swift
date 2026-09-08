import SwiftUI

/// Making a new time of day: when it is, and what it asks.
///
/// The plus on the library used to insert a named block and save it before the
/// user had decided anything, then push the editor for an object that already
/// existed. Backing out left a sitting nobody asked for — invisible on Today,
/// since a promptless block is filtered out there, but sitting in the settings
/// list waiting to be deleted.
///
/// So creation is its own verb, on its own surface, and nothing reaches the
/// database until the last button. `BlockDetailView` stays what it is: a live
/// editor for a block that exists, with no save button to explain.
///
/// Two steps rather than one because the question list wants a whole screen,
/// and rather than three because this is a settings task and not a second
/// onboarding.
struct NewBlockView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .when
    @State private var hour: Int
    @State private var minute: Int
    /// In the order they were picked, which becomes the order they're answered.
    /// Drafts rather than variants, because a question the user writes here has
    /// no catalog entry to point at.
    @State private var picked: [PromptDraft] = []
    /// The draft being written or revised. Non-nil presents the editor.
    @State private var editing: EditorTarget?

    init(hour: Int, minute: Int) {
        _hour = State(initialValue: hour)
        _minute = State(initialValue: minute)
    }

    private enum Step: Int, CaseIterable {
        case when
        case questions
    }

    /// What the editor sheet was opened for. `Identifiable` so the sheet is
    /// driven by the thing itself rather than a bool plus a second variable
    /// that can disagree with it.
    private enum EditorTarget: Identifiable {
        case new
        case revising(PromptDraft)

        var id: String {
            switch self {
            case .new: "new"
            case let .revising(draft): draft.id.uuidString
            }
        }

        var draft: PromptDraft? {
            switch self {
            case .new: nil
            case let .revising(draft): draft
            }
        }
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            VStack(spacing: 0) {
                header

                Group {
                    switch step {
                    case .when: whenStep
                    case .questions: questionsStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(Theme.Motion.settle, value: step)

                footer
            }
        }
        .onAppear { Haptics.prepare() }
        .sheet(item: $editing) { target in
            PromptEditorView(
                prompt: nil,
                block: nil,
                draft: target.draft,
                onDraft: { record($0) },
                // Only offered when there is something to remove.
                onRemoveDraft: target.draft.map { draft in
                    { remove(draft) }
                }
            )
        }
    }

    // MARK: - Chrome

    /// The same shape the journal session wears: where you are, a way back, and
    /// a way out, over a rule that fills as you go.
    private var header: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                if step == .questions {
                    IconButton(systemName: "chevron.left", accessibilityTitle: "Back") {
                        withAnimation(Theme.Motion.settle) { step = .when }
                    }
                    .transition(.opacity)
                } else {
                    Color.clear.frame(
                        width: Theme.Space.iconControl,
                        height: Theme.Space.iconControl
                    )
                }

                Spacer(minLength: 0)

                Text("\(step.rawValue + 1) OF \(Step.allCases.count)")
                    .eyebrowStyle(Theme.Palette.inkTertiary)

                Spacer(minLength: 0)

                IconButton(systemName: "xmark", accessibilityTitle: "Cancel", size: 12) {
                    dismiss()
                }
            }
            .animation(Theme.Motion.quick, value: step)

            ProgressRule(progress: Double(step.rawValue) / Double(Step.allCases.count - 1))
        }
        .pageGutter()
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.lg)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            // Above the button, and held in the layout rather than inserted, so
            // the step above doesn't shift as it comes and goes.
            if step == .questions {
                Text("Pick at least one question.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .opacity(picked.isEmpty ? 1 : 0)
                    .accessibilityHidden(!picked.isEmpty)
            }

            EmberButton(
                title: step == .when ? "Continue" : "Add this time",
                systemImage: step == .when ? nil : "checkmark",
                isEnabled: step == .when || !picked.isEmpty
            ) {
                advance()
            }
        }
        .animation(Theme.Motion.quick, value: picked.isEmpty)
        .pageGutter()
        .padding(.bottom, Theme.Space.md)
    }

    // MARK: - Step one: when

    private var whenStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                // Says what this costs before it's made, because the answer
                // is no longer a pair of switches on the next screen: every
                // block locks the phone and every block reminds.
                heading(
                    "A new time of day",
                    "When do you want to sit down? Your phone stays shut until this page is written."
                )

                GlassCard {
                    VStack(spacing: Theme.Space.md) {
                        DatePicker(
                            "Time",
                            selection: TimeBinding.make(hour: $hour, minute: $minute),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Time")
                    }
                }

                Color.clear.frame(height: Theme.Space.lg)
            }
            .pageGutter()
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Step two: what it asks

    private var questionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                heading("What will you answer?", costLine)

                GhostButton(title: "Write your own", systemImage: "square.and.pencil") {
                    editing = .new
                }

                // The user's own wordings, above the shelf they didn't come
                // from. A written question has nowhere else to appear — unlike
                // a catalog row, unpicking it is the only copy gone — so these
                // open for revision on tap instead of vanishing.
                if !written.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("Yours").eyebrowStyle(Theme.Palette.emberDeep)

                        ForEach(written) { draft in
                            writtenRow(draft)
                        }
                    }
                }

                ForEach(PromptRole.allCases) { role in
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text(role.label).eyebrowStyle(Theme.Palette.emberDeep)

                        ForEach(role.alternates) { variant in
                            variantRow(variant)
                        }
                    }
                }

                Color.clear.frame(height: Theme.Space.lg)
            }
            .pageGutter()
        }
        .scrollIndicators(.hidden)
    }

    /// What the sitting will cost, kept live as they pick. The one number
    /// setup enthusiasm must not be allowed to inflate — the same reason the
    /// onboarding plan screen carries it.
    private var costLine: String {
        guard !picked.isEmpty else {
            return "Pick as many as you like. You can reword any of them later."
        }
        let seconds = picked.reduce(0) { $0 + $1.style.estimatedSeconds }
        let count = picked.count
        let questions = "\(count) question\(count == 1 ? "" : "s")"
        return "\(questions), \(PromptTemplate.duration(seconds: seconds).lowercased())."
    }

    /// The questions the user wrote here, in the order they wrote them.
    private var written: [PromptDraft] {
        picked.filter { $0.originKey.isEmpty }
    }

    private func writtenRow(_ draft: PromptDraft) -> some View {
        row(
            title: draft.title,
            style: draft.style,
            isPicked: true,
            trailing: "pencil",
            hint: "Edit this question"
        ) {
            Haptics.tap(.light)
            editing = .revising(draft)
        }
    }

    private func variantRow(_ variant: PromptVariant) -> some View {
        let isPicked = picked.contains { $0.originKey == variant.key }

        return row(
            title: variant.title,
            style: variant.style,
            isPicked: isPicked,
            trailing: isPicked ? "checkmark.circle.fill" : "circle",
            hint: isPicked ? "Remove this question" : "Add this question"
        ) {
            toggle(variant)
        }
    }

    private func row(
        title: String,
        style: PromptStyle,
        isPicked: Bool,
        trailing: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassCard(
                tint: isPicked
                    ? Theme.Palette.emberSoft.opacity(0.34)
                    : Theme.Palette.ink.opacity(0.04),
                padding: Theme.Space.md
            ) {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Theme.Typography.serif(17))
                            .foregroundStyle(Theme.Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(styleLabel(style))
                            .font(Theme.Typography.sans(11))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }

                    Spacer(minLength: Theme.Space.xs)

                    Image(systemName: trailing)
                        .font(.system(size: 17, weight: isPicked ? .semibold : .regular))
                        .foregroundStyle(
                            isPicked ? Theme.Palette.emberDeep : Theme.Palette.inkTertiary
                        )
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(hint)
    }

    private func styleLabel(_ style: PromptStyle) -> String {
        switch style {
        case .freeform: "Open answer"
        case let .lines(count): "\(count) line\(count == 1 ? "" : "s")"
        }
    }

    // MARK: - Shared

    private func heading(_ title: String, _ blurb: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.Typography.serif(32))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(blurb)
                .font(Theme.Typography.sans(15))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .animation(Theme.Motion.quick, value: blurb)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func toggle(_ variant: PromptVariant) {
        withAnimation(Theme.Motion.quick) {
            if let index = picked.firstIndex(where: { $0.originKey == variant.key }) {
                picked.remove(at: index)
                Haptics.tap(.light)
            } else {
                picked.append(PromptDraft(variant))
                Haptics.selection()
            }
        }
    }

    /// Files a question back from the editor — in place when it was already in
    /// the list, at the end when it is new.
    private func record(_ draft: PromptDraft) {
        withAnimation(Theme.Motion.quick) {
            if let index = picked.firstIndex(where: { $0.id == draft.id }) {
                picked[index] = draft
            } else {
                picked.append(draft)
            }
        }
    }

    private func remove(_ draft: PromptDraft) {
        withAnimation(Theme.Motion.quick) {
            picked.removeAll { $0.id == draft.id }
        }
    }

    private func advance() {
        switch step {
        case .when:
            withAnimation(Theme.Motion.settle) { step = .questions }
        case .questions:
            guard !picked.isEmpty else { return }
            store.createBlock(
                hour: hour,
                minute: minute,
                prompts: picked
            )
            Haptics.success()
            dismiss()
        }
    }
}
