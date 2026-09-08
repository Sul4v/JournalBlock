import SwiftUI
import SwiftData

/// One block, opened: its time, its name, what it does, and its prompts.
///
/// Everything that used to be crammed into the block's row on the list — a
/// time picker, an inline name field, a menu of switches, a button per prompt —
/// lives here instead. The list is now a list; this is the editor.
struct BlockDetailView: View {
    @Environment(\.journalStore) private var store
    @Environment(\.dismiss) private var dismiss

    @Bindable var block: JournalBlock

    @Query(sort: \JournalPrompt.order) private var library: [JournalPrompt]

    @State private var editing: JournalPrompt?
    @State private var isAdding = false
    /// The prompt whose deletion was just refused, so the row can say why.
    @State private var strandedPrompt: UUID?
    @State private var isConfirmingDelete = false
    /// Whether the wheel is open under the time.
    @State private var isPickingTime = false
    /// Set when deleting the last block standing is refused, which puts the
    /// reason in front of the user rather than leaving the tap looking broken.
    @State private var refusedDelete = false

    private var prompts: [JournalPrompt] {
        library.filter { $0.blockID == block.id }
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    settingsCard
                    promptsSection

                    Color.clear.frame(height: Theme.Space.lg)
                }
                .pageGutter()
                .padding(.top, Theme.Space.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        // Asked and answered in one step when there's nothing
                        // to ask: a confirmation that can only be refused is a
                        // dead end, so the last block explains itself instead.
                        if store.blocks().count > 1 {
                            isConfirmingDelete = true
                        } else {
                            refusedDelete = true
                            Haptics.warning()
                        }
                    } label: {
                        Label("Delete block", systemImage: "trash")
                    }
                } label: {
                    // Bare glyph, not `ellipsis.circle`: iOS draws its own
                    // round glass button behind a toolbar item, and the
                    // circled symbol put a second ring inside the first.
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .accessibilityLabel("Block options")
            }
        }
        .sheet(item: $editing) { prompt in
            PromptEditorView(prompt: prompt, block: block)
        }
        .sheet(isPresented: $isAdding) {
            PromptPickerView(block: block)
        }
        // An alert, not a confirmation dialog. Raised from a toolbar menu, a
        // confirmation dialog presents as a popover that anchors itself to
        // whatever it was attached to — off the root view it pointed at the
        // middle of the page and laid its body across the navigation bar, and
        // off the menu it still covered the title and dropped Cancel. A
        // destructive question deserves the middle of the screen and two
        // plainly labelled ways out, which is what the refusal below already
        // does.
        .alert("Delete \(block.timeLabel)?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the block and its prompts. What you've already written stays in your entries.")
        }
        // Modal rather than a line of red text on the page: the delete lives in
        // the toolbar now, and a note at the bottom of a scrolled screen is a
        // refusal the user never sees.
        .alert("Keep at least one block", isPresented: $refusedDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your journal needs somewhere to write.")
        }
    }

    // MARK: - The block itself

    private var settingsCard: some View {
        GlassCard {
            VStack(spacing: Theme.Space.md) {
                timeRow

                Divider().overlay(Theme.Palette.rule)

                // Stated, not offered. Both were switches until every block
                // started doing both; a toggle that can only be on is a
                // decision the screen pretends the user still has.
                Text("Locks your phone until this page is written, and reminds you at \(block.timeLabel).")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The block's time, as the heading this screen no longer has in its
    /// navigation bar.
    ///
    /// A compact `DatePicker` put the one fact the screen exists to show into
    /// a small grey chip the same size as a toggle — the block's whole
    /// identity, styled as a minor setting. So the time is set in the app's
    /// own type, and the system wheel unfolds underneath only when it's being
    /// changed, which keeps the prompts within reach the rest of the time.
    private var timeRow: some View {
        VStack(spacing: Theme.Space.sm) {
            Button {
                Haptics.tap(.light)
                withAnimation(Theme.Motion.settle) { isPickingTime.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                    Text(block.timeLabel)
                        .font(Theme.Typography.serif(34))
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText())

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            isPickingTime ? Theme.Palette.emberDeep : Theme.Palette.inkTertiary
                        )
                        .rotationEffect(.degrees(isPickingTime ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Time")
            .accessibilityValue(block.timeLabel)
            .accessibilityHint(isPickingTime ? "Closes the time picker" : "Opens the time picker")

            if isPickingTime {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { block.date() },
                        set: { newValue in
                            let parts = Calendar.current.dateComponents(
                                [.hour, .minute], from: newValue
                            )
                            store.setTime(
                                hour: parts.hour ?? block.hour,
                                minute: parts.minute ?? block.minute,
                                on: block
                            )
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Prompts

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .center) {
                SectionHeading(title: "Prompts")

                Button {
                    Haptics.tap(.light)
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.emberDeep)
                        .frame(width: Theme.Space.tapTarget, height: Theme.Space.tapTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New prompt")
            }

            if prompts.isEmpty {
                Text("Nothing here yet. Add a prompt and this time appears on your Today screen.")
                    .font(Theme.Typography.sans(13))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Theme.Space.xs)
            }

            ForEach(prompts) { prompt in
                PromptRow(
                    prompt: prompt,
                    isStranded: strandedPrompt == prompt.id,
                    onEdit: { editing = prompt },
                    onDelete: { delete(prompt) },
                    onEnable: { store.setEnabled(true, on: prompt) }
                )
            }
        }
    }

    // MARK: - Actions

    /// Refused when it would leave a gating block with no questions at all —
    /// the one rule the library enforces. The row says why, rather than the
    /// long-press menu quietly doing nothing.
    private func delete(_ prompt: JournalPrompt) {
        if store.deletePrompt(prompt) {
            Haptics.success()
            strandedPrompt = nil
        } else {
            strandedPrompt = prompt.id
            Haptics.warning()
        }
    }

    private func delete() {
        guard store.deleteBlock(block) else {
            refusedDelete = true
            Haptics.warning()
            return
        }
        Haptics.success()
        // Pop first: this screen is bound to a block that no longer exists.
        dismiss()
    }

}

// MARK: - Pieces

/// One prompt: tap to edit it, long-press to delete it.
///
/// The switch that used to sit here is gone. "Off" and "deleted" were the same
/// intention wearing two hats, and a row of switches turned a page of questions
/// into a control panel — see `JournalStore.wouldStrandGate` for the one case
/// deletion is refused.
private struct PromptRow: View {
    @Bindable var prompt: JournalPrompt
    /// True when the user just tried to delete the last question of a block
    /// that locks the phone.
    var isStranded: Bool = false
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Switching a prompt off is no longer possible, but a library restored
    /// from an older build can still arrive with one off — this is the way
    /// back, and it appears on nothing else.
    let onEnable: () -> Void

    var body: some View {
        Button(action: onEdit) {
            GlassCard(
                tint: prompt.isEnabled
                    ? Theme.Palette.emberSoft.opacity(0.20)
                    : Theme.Palette.ink.opacity(0.03),
                padding: Theme.Space.md
            ) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(Theme.Typography.serif(17))
                            .foregroundStyle(prompt.isEnabled ? Theme.Palette.ink : Theme.Palette.inkTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Text(styleLabel)
                            if !prompt.isEnabled {
                                Text("·")
                                Text("Off")
                            }
                        }
                        .font(Theme.Typography.sans(11))
                        .foregroundStyle(Theme.Palette.inkTertiary)

                        // Only appears after a delete is refused, so the rule
                        // is explained at the moment it bites rather than
                        // sitting on screen as a permanent warning.
                        if isStranded {
                            Text("This block locks your phone, so it needs at least one question.")
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
                .frame(minHeight: Theme.Space.tapTarget - Theme.Space.md)
            }
        }
        .buttonStyle(.plain)
        // Without this the long-press lifts the row onto a square platter and
        // draws a rectangle around a card that is visibly rounded. The preview
        // has to be told the shape; it doesn't read it off the glass.
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .contextMenu {
            if !prompt.isEnabled {
                Button {
                    onEnable()
                } label: {
                    Label("Turn on", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete prompt", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this prompt. Long press to delete it.")
        .animation(Theme.Motion.quick, value: isStranded)
    }

    private var styleLabel: String {
        switch prompt.style {
        case .freeform: "Open answer"
        case let .lines(count): "\(count) line\(count == 1 ? "" : "s")"
        }
    }
}
