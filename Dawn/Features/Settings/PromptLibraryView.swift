import SwiftUI
import SwiftData

/// Where the journal becomes the user's own. Built-in prompts can be reworded
/// or switched off; custom ones can be anything.
struct PromptLibraryView: View {
    @Environment(\.journalStore) private var store
    @Query(sort: \JournalPrompt.order) private var prompts: [JournalPrompt]

    @State private var editing: JournalPrompt?
    @State private var isAdding = false
    /// The prompt whose toggle was just refused, so the row can say why.
    @State private var strandedPrompt: UUID?

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    ForEach(JournalPrompt.Session.allCases) { session in
                        let group = prompts.filter { $0.session == session }
                        if !group.isEmpty {
                            VStack(spacing: Theme.Space.sm) {
                                SectionHeading(
                                    eyebrow: session.label,
                                    title: session == .morning ? "Before the day" : "After the day"
                                )
                                ForEach(group) { prompt in
                                    PromptRow(
                                        prompt: prompt,
                                        isStranded: strandedPrompt == prompt.id
                                    ) {
                                        editing = prompt
                                    } onToggle: {
                                        // Refused when it would leave the
                                        // morning with no questions at all.
                                        if store.setEnabled(!prompt.isEnabled, on: prompt) {
                                            Haptics.tap(.light)
                                        } else {
                                            strandedPrompt = prompt.id
                                            Haptics.warning()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GhostButton(title: "New prompt", systemImage: "plus") {
                        isAdding = true
                    }
                    .padding(.top, Theme.Space.xs)

                    Color.clear.frame(height: Theme.Space.lg)
                }
                .pageGutter()
                .padding(.top, Theme.Space.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Prompts")
                    .font(Theme.Typography.serif(17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .sheet(item: $editing) { prompt in
            PromptEditorView(prompt: prompt)
        }
        .sheet(isPresented: $isAdding) {
            PromptEditorView(prompt: nil)
        }
    }
}

private struct PromptRow: View {
    @Bindable var prompt: JournalPrompt
    /// True when the user just tried to switch off the last morning question.
    var isStranded: Bool = false
    let onEdit: () -> Void
    let onToggle: () -> Void

    var body: some View {
        GlassCard(
            tint: prompt.isEnabled
                ? Theme.Palette.emberSoft.opacity(0.20)
                : Theme.Palette.ink.opacity(0.03),
            padding: Theme.Space.md
        ) {
            HStack(alignment: .center, spacing: Theme.Space.sm) {
                // The row itself opens the editor — a separate pencil button
                // squeezed the prompt text into three-line wraps.
                Button(action: onEdit) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.title)
                                .font(Theme.Typography.serif(17))
                                .foregroundStyle(prompt.isEnabled ? Theme.Palette.ink : Theme.Palette.inkTertiary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                Text(styleLabel)
                                if let source {
                                    Text("·")
                                    Text(source)
                                }
                            }
                            .font(Theme.Typography.sans(11))
                            .foregroundStyle(Theme.Palette.inkTertiary)

                            // Only appears after the toggle refuses, so the
                            // rule is explained at the moment it bites rather
                            // than sitting on screen as a permanent warning.
                            if isStranded {
                                Text("Your morning needs at least one question.")
                                    .font(Theme.Typography.sans(11))
                                    .foregroundStyle(Theme.Palette.emberDeep)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            }
                        }

                        Spacer(minLength: Theme.Space.xs)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Theme.Space.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Edit this prompt")

                // `labelsHidden()` left VoiceOver announcing "switch, on"
                // with no way to tell which of five prompts it belonged to.
                Toggle("", isOn: Binding(get: { prompt.isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .tint(Theme.Palette.ember)
                    .accessibilityLabel(prompt.title)
                    .accessibilityHint("Include this prompt in the session")
            }
        }
        .animation(Theme.Motion.quick, value: isStranded)
    }

    private var styleLabel: String {
        switch prompt.style {
        case .freeform: "Open answer"
        case let .lines(count): "\(count) line\(count == 1 ? "" : "s")"
        }
    }

    /// Where this question came from, when it came from somewhere. A prompt the
    /// user wrote says nothing — "Custom" would be labelling the normal case.
    private var source: String? {
        guard !prompt.originTemplateID.isEmpty else { return nil }
        return PromptTemplate.template(id: prompt.originTemplateID)?.name
    }
}

/// Create or edit a single prompt.
struct PromptEditorView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss

    let prompt: JournalPrompt?

    @State private var title: String
    @State private var hint: String
    @State private var lineCount: Int
    @State private var styleKind: PromptStyle.Kind
    @State private var session: JournalPrompt.Session
    @FocusState private var titleFocused: Bool

    init(prompt: JournalPrompt?) {
        self.prompt = prompt
        _title = State(initialValue: prompt?.title ?? "")
        _hint = State(initialValue: prompt?.hint ?? "")
        _lineCount = State(initialValue: prompt?.style.slotCount ?? 1)
        _styleKind = State(initialValue: prompt?.style.kind ?? .lines)
        _session = State(initialValue: prompt?.session ?? .morning)
    }

    private var canSave: Bool { !title.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(phase: .sunrise, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        field(label: "Prompt", text: $title, placeholder: "What are you looking forward to?")
                            .focused($titleFocused)
                        field(label: "Hint", text: $hint, placeholder: "Optional nudge under the question")

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text("Room to write").eyebrowStyle()
                            // A list and a paragraph are different questions.
                            // "Three things I'm grateful for" wants ruled
                            // lines; "what's sitting on my chest" wants a box
                            // that grows, and three stubby fields turn it into
                            // a form. Without this control, editing a prompt
                            // that shipped as open would silently flatten it.
                            Picker("Answer", selection: $styleKind) {
                                Text("Lines").tag(PromptStyle.Kind.lines)
                                Text("Open answer").tag(PromptStyle.Kind.freeform)
                            }
                            .pickerStyle(.segmented)

                            if styleKind == .lines {
                                Picker("Lines", selection: $lineCount) {
                                    ForEach(1...PromptStyle.maxLines, id: \.self) { Text("\($0)").tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .transition(.opacity)
                            }
                        }
                        .animation(Theme.Motion.quick, value: styleKind)

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text("When").eyebrowStyle()
                            Picker("When", selection: $session) {
                                ForEach(JournalPrompt.Session.allCases) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(prompt?.isBuiltIn == true)
                        }

                        // Anything can be deleted now, template rows included —
                        // the only thing protected is having a morning at all.
                        if let prompt, !store.wouldStrandMorning(prompt) {
                            GhostButton(title: "Delete prompt", systemImage: "trash", isNested: false) {
                                store.deletePrompt(prompt)
                                dismiss()
                            }
                            .padding(.top, Theme.Space.sm)
                        }
                    }
                    .pageGutter()
                    .padding(.top, Theme.Space.md)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(prompt == nil ? "New prompt" : "Edit prompt")
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
                if prompt == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { titleFocused = true }
                }
            }
        }
    }

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).eyebrowStyle()
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "",
                    text: text,
                    prompt: Text(placeholder)
                        .font(Theme.Typography.serif(19))
                        .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.7)),
                    axis: .vertical
                )
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Palette.ink)
                .tint(Theme.Palette.ember)

                Rectangle().fill(Theme.Palette.rule).frame(height: 1)
            }
        }
    }

    private func save() {
        if let prompt {
            prompt.title = title.trimmed
            prompt.hint = hint.trimmed
            prompt.style = .make(kind: styleKind, lineCount: lineCount)
            if !prompt.isBuiltIn { prompt.session = session }
            store.save()
        } else {
            store.addPrompt(
                title: title.trimmed,
                hint: hint.trimmed,
                style: .make(kind: styleKind, lineCount: lineCount),
                session: session
            )
        }
        Haptics.success()
        dismiss()
    }
}
