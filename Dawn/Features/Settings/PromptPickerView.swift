import SwiftUI

/// The list of questions to choose from when adding a prompt to a block.
///
/// Picking a wording is the move this feature leans on. Writing a good prompt
/// from nothing is harder than journaling — most people asked to fill an empty
/// "Prompt" field either write something they'll wince at in a week or close
/// the sheet. Choosing between six phrasings of "gratitude" takes two seconds,
/// so that is what the sheet opens on, with the blank field one tap away.
struct PromptPickerView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss

    let block: JournalBlock

    @State private var isWritingOwn = false

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(phase: DayPhase.current(), intensity: 0.55)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        Text("Pick a question for \(block.timeLabel), or write your own.")
                            .font(Theme.Typography.sans(14))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        GhostButton(title: "Write your own", systemImage: "square.and.pencil") {
                            isWritingOwn = true
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
                    .padding(.top, Theme.Space.sm)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Add a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isWritingOwn) {
                PromptEditorView(prompt: nil, block: block, onSave: { dismiss() })
            }
        }
    }

    private func variantRow(_ variant: PromptVariant) -> some View {
        Button {
            store.addPrompt(variant, to: block)
            Haptics.success()
            dismiss()
        } label: {
            GlassCard(padding: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(variant.title)
                            .font(Theme.Typography.serif(17))
                            .foregroundStyle(Theme.Palette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(styleLabel(variant.style))
                            .font(Theme.Typography.sans(11))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }

                    Spacer(minLength: Theme.Space.xs)

                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.emberDeep)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Add this prompt")
    }

    private func styleLabel(_ style: PromptStyle) -> String {
        switch style {
        case .freeform: "Open answer"
        case let .lines(count): "\(count) line\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Editor

/// Create or edit a single prompt.
///
/// Built as the thing itself rather than a form about it: the card at the top
/// is the prompt as it will look at 6am — serif question, grey hint, and the
/// room the answer gets — and editing happens directly on it. The old version
/// asked for "Prompt", "Hint" and "Room to write" in three labelled fields and
/// left the user to imagine the result, which is how prompts ended up with
/// three stubby lines where they wanted a paragraph.
struct PromptEditorView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss

    let prompt: JournalPrompt?
    /// Which block this belongs to. For a new prompt it's where it lands; for
    /// an existing one it's the starting value of the picker.
    let block: JournalBlock?
    /// Called after a successful save, so a picker that presented this sheet
    /// can close itself behind it rather than leaving the user two taps deep.
    var onSave: (() -> Void)?
    /// A question being written for a block that doesn't exist yet.
    ///
    /// Set by the block creation flow, and the switch that puts this editor in
    /// draft mode: nothing is written to the store, `onDraft` is handed the
    /// finished question instead, and the block picker disappears because the
    /// only block it could offer is the one being made. `draft` non-nil means
    /// an existing draft is being revised rather than a new one written.
    var draft: PromptDraft?
    var onDraft: ((PromptDraft) -> Void)?
    /// Drops a draft being revised. Stands in for `deleteButton`, which needs a
    /// saved prompt to delete.
    var onRemoveDraft: (() -> Void)?

    /// True when this editor writes nothing and reports back instead.
    private var isDrafting: Bool { onDraft != nil }

    @State private var title: String
    @State private var hint: String
    @State private var lineCount: Int
    @State private var styleKind: PromptStyle.Kind
    @State private var blockID: UUID?
    /// Set when moving the prompt out of a gating block was refused.
    @State private var refusedMove = false
    @FocusState private var focus: Field?

    private enum Field { case title, hint }

    init(
        prompt: JournalPrompt?,
        block: JournalBlock?,
        onSave: (() -> Void)? = nil,
        draft: PromptDraft? = nil,
        onDraft: ((PromptDraft) -> Void)? = nil,
        onRemoveDraft: (() -> Void)? = nil
    ) {
        self.prompt = prompt
        self.block = block
        self.onSave = onSave
        self.draft = draft
        self.onDraft = onDraft
        self.onRemoveDraft = onRemoveDraft
        _title = State(initialValue: prompt?.title ?? draft?.title ?? "")
        _hint = State(initialValue: prompt?.hint ?? draft?.hint ?? "")
        _lineCount = State(initialValue: prompt?.style.slotCount ?? draft?.style.slotCount ?? 1)
        _styleKind = State(initialValue: prompt?.style.kind ?? draft?.style.kind ?? .lines)
        _blockID = State(initialValue: prompt?.blockID ?? block?.id)
    }

    private var canSave: Bool { !title.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(phase: .sunrise, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        promptCard
                        roomCard
                        whenCard
                        deleteButton

                        Color.clear.frame(height: Theme.Space.lg)
                    }
                    .pageGutter()
                    .padding(.top, Theme.Space.md)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(prompt == nil && draft == nil ? "New prompt" : "Edit prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                if prompt == nil && draft == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .title }
                }
            }
        }
    }

    // MARK: - The prompt, as it will look

    private var promptCard: some View {
        GlassCard(padding: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "",
                        text: $title,
                        prompt: Text("Ask yourself something…")
                            .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.7)),
                        axis: .vertical
                    )
                    .font(Theme.Typography.serif(26))
                    .foregroundStyle(Theme.Palette.ink)
                    .tint(Theme.Palette.ember)
                    .lineSpacing(3)
                    .focused($focus, equals: .title)
                    .accessibilityLabel("Prompt")

                    TextField(
                        "",
                        text: $hint,
                        prompt: Text("Add a hint — optional")
                            .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.7)),
                        axis: .vertical
                    )
                    .font(Theme.Typography.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .tint(Theme.Palette.ember)
                    .focused($focus, equals: .hint)
                    .accessibilityLabel("Hint")
                }

                answerPreview
            }
        }
    }

    /// The space the answer gets, drawn but not typeable. It's what makes the
    /// line count mean something while you're choosing it.
    private var answerPreview: some View {
        VStack(spacing: Theme.Space.sm) {
            if styleKind == .freeform {
                previewLine(label: "…", minHeight: 84)
            } else {
                ForEach(0..<lineCount, id: \.self) { index in
                    previewLine(
                        label: lineCount == 1 ? "…" : "\(index + 1).",
                        minHeight: 0
                    )
                }
            }
        }
        .animation(Theme.Motion.quick, value: lineCount)
        .animation(Theme.Motion.quick, value: styleKind)
        .accessibilityElement()
        .accessibilityLabel(roomLabel)
    }

    private func previewLine(label: String, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            Rectangle()
                .fill(Theme.Palette.rule)
                .frame(height: 1)
        }
    }

    // MARK: - Controls

    private var roomCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Room to write").eyebrowStyle()

            GlassCard {
                VStack(spacing: Theme.Space.md) {
                    // A list and a paragraph are different questions. "Three
                    // things I'm grateful for" wants ruled lines; "what's
                    // sitting on my chest" wants a box that grows, and three
                    // stubby fields turn it into a form.
                    Picker("Answer", selection: $styleKind) {
                        Text("Lines").tag(PromptStyle.Kind.lines)
                        Text("Open answer").tag(PromptStyle.Kind.freeform)
                    }
                    .pickerStyle(.segmented)

                    if styleKind == .lines {
                        Divider().overlay(Theme.Palette.rule)

                        // A stepper rather than a five-wide segmented control:
                        // the count is already shown full size in the card
                        // above, so this only has to nudge it.
                        HStack {
                            Text("How many")
                                .font(Theme.Typography.sans(16))
                                .foregroundStyle(Theme.Palette.ink)

                            Spacer()

                            stepButton("minus", enabled: lineCount > 1) {
                                lineCount -= 1
                            }

                            Text("\(lineCount)")
                                .font(Theme.Typography.sans(17, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.ink)
                                .frame(minWidth: 28)
                                .contentTransition(.numericText())

                            stepButton("plus", enabled: lineCount < PromptStyle.maxLines) {
                                lineCount += 1
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(Theme.Motion.quick, value: styleKind)
    }

    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap(.light)
            withAnimation(Theme.Motion.quick) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Theme.Palette.ink : Theme.Palette.inkTertiary.opacity(0.4))
                .frame(width: Theme.Space.tapTarget, height: Theme.Space.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "One more line" : "One fewer line")
    }

    /// Which block the prompt sits in. This is the old morning/evening
    /// segmented control, grown up: the same choice, with the user's own times
    /// in it instead of two the app picked.
    @ViewBuilder
    private var whenCard: some View {
        let blocks = store.blocks()
        if blocks.count > 1 && !isDrafting {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("When").eyebrowStyle()

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Menu {
                            Picker("When", selection: $blockID) {
                                ForEach(blocks) { block in
                                    Text(block.timeLabel).tag(block.id as UUID?)
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedBlockLabel(blocks))
                                    .font(Theme.Typography.sans(16))
                                    .foregroundStyle(Theme.Palette.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.inkTertiary)
                            }
                            .frame(minHeight: Theme.Space.tapTarget - Theme.Space.sm)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("When")

                        if refusedMove {
                            Text("This block locks your phone, so it needs at least one question.")
                                .font(Theme.Typography.sans(11))
                                .foregroundStyle(Theme.Palette.emberDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if let onRemoveDraft {
            HStack {
                Spacer()
                GhostButton(title: "Remove question", systemImage: "trash") {
                    onRemoveDraft()
                    dismiss()
                }
                Spacer()
            }
        } else if let prompt, !store.wouldStrandGate(prompt) {
            HStack {
                Spacer()
                GhostButton(title: "Delete prompt", systemImage: "trash") {
                    store.deletePrompt(prompt)
                    dismiss()
                }
                Spacer()
            }
        }
    }

    // MARK: - Copy

    private func selectedBlockLabel(_ blocks: [JournalBlock]) -> String {
        guard let block = blocks.first(where: { $0.id == blockID }) else { return "Choose a time" }
        return block.timeLabel
    }

    private var roomLabel: String {
        styleKind == .freeform
            ? "Open answer"
            : "\(lineCount) line\(lineCount == 1 ? "" : "s")"
    }

    // MARK: - Saving

    private func save() {
        // Draft mode writes nothing. The id carries across so revising a draft
        // replaces it in the caller's list rather than adding a second copy.
        if let onDraft {
            onDraft(
                PromptDraft(
                    id: draft?.id ?? UUID(),
                    title: title.trimmed,
                    hint: hint.trimmed,
                    style: .make(kind: styleKind, lineCount: lineCount),
                    originKey: draft?.originKey ?? ""
                )
            )
            Haptics.success()
            dismiss()
            return
        }

        let destination = blockID.flatMap { store.block(id: $0) } ?? block
        if let prompt {
            prompt.title = title.trimmed
            prompt.hint = hint.trimmed
            prompt.style = .make(kind: styleKind, lineCount: lineCount)
            if let destination, destination.id != prompt.blockID {
                guard store.move(prompt, to: destination) else {
                    refusedMove = true
                    Haptics.warning()
                    return
                }
            }
            store.save()
        } else {
            guard let destination else { return }
            store.addPrompt(
                title: title.trimmed,
                hint: hint.trimmed,
                style: .make(kind: styleKind, lineCount: lineCount),
                to: destination
            )
        }
        Haptics.success()
        dismiss()
        onSave?()
    }
}
