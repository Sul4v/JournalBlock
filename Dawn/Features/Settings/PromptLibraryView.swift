import SwiftUI
import SwiftData

/// The shape of the user's day: as many blocks as they want, each at a time
/// they choose, each with its own prompts.
///
/// This screen replaced a fixed two-section list — "Before the day" and "After
/// the day" — which quietly made two decisions for everyone: that they wanted
/// an evening reflection, and that they couldn't have a third sitting at any
/// price. Both were the app's opinion wearing the clothes of a layout.
///
/// Deliberately read-only. Every control it once carried inline — a time
/// picker, a name field, a menu, a switch per prompt — now lives one tap away
/// in `BlockDetailView`, which leaves this screen able to answer the only
/// question it should: what does my day look like?
struct PromptLibraryView: View {
    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs

    @Query(
        sort: [
            SortDescriptor(\JournalBlock.hour),
            SortDescriptor(\JournalBlock.minute),
            SortDescriptor(\JournalBlock.order)
        ]
    ) private var blocks: [JournalBlock]
    @Query(sort: \JournalPrompt.order) private var prompts: [JournalPrompt]

    /// The block being edited. Set by tapping a card.
    @State private var opened: JournalBlock?
    /// The creation flow. A sheet rather than a push, because making a block is
    /// a different verb from editing one: it commits at the end, and closing it
    /// leaves nothing behind.
    @State private var isCreating = false
    @State private var isEditing = false
    /// The block whose minus was tapped, waiting on the confirmation.
    @State private var pendingDelete: JournalBlock?
    /// Set when deleting the last block standing was refused.
    @State private var refusedDelete = false

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.55)

            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    intro

                    ForEach(blocks) { block in
                        blockRow(block)
                    }

                    // No label: the cards above are times of day, and a plus
                    // under them doesn't need telling what it adds. `IconButton`
                    // brings its own tap haptic and 44pt target.
                    IconButton(
                        systemName: "plus",
                        accessibilityTitle: "Add a time of day",
                        size: 16,
                        diameter: Theme.Space.tapTarget
                    ) {
                        isCreating = true
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
                Text("Your Blocks")
                    .font(Theme.Typography.serif(17, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
            }

            ToolbarItem(placement: .topBarTrailing) {
                // Hidden on the last block standing: it can't be deleted, so
                // an Edit mode whose only control is a refusal is a button
                // that does nothing.
                if blocks.count > 1 {
                    Button(isEditing ? "Done" : "Edit") {
                        Haptics.tap(.light)
                        withAnimation(Theme.Motion.settle) { isEditing.toggle() }
                    }
                    .font(Theme.Typography.sans(16, weight: isEditing ? .semibold : .regular))
                    .foregroundStyle(Theme.Palette.emberDeep)
                }
            }
        }
        // One tap on the minus is not enough on its own: this takes the
        // block's prompts with it, and there is no way back.
        .alert(
            "Delete \(pendingDelete?.timeLabel ?? "")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { block in
            Button("Delete", role: .destructive) { delete(block) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the block and its prompts. What you've already written stays in your entries.")
        }
        // Deleting the last block is refused rather than allowed: a journal
        // with nowhere to write is a state this screen can't get back out of.
        .alert("Keep at least one block", isPresented: $refusedDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your journal needs somewhere to write.")
        }
        .navigationDestination(item: $opened) { block in
            BlockDetailView(block: block)
        }
        .sheet(isPresented: $isCreating) {
            let slot = store.nextBlockSlot()
            // Straight back to the list, where the new card animates in. The
            // flow has already asked the two questions the editor would;
            // pushing into it would be handing back a screen they just filled.
            NewBlockView(hour: slot.hour, minute: slot.minute)
        }
        // Times and reminder switches are edited on the next screen with no
        // save button, so the schedule is rebuilt whenever any of them settles.
        // This view stays mounted underneath, which makes it the one place that
        // sees every block change without having to be told about it.
        .onChange(of: blocks.count) { _, count in
            if count <= 1 { isEditing = false }
        }
        .onChange(of: reminderFingerprint) { _, _ in rearmSchedules() }
    }

    /// Re-points both schedules at the times the blocks now hold. Without it
    /// an alarm goes on ringing at the hour a block used to be.
    ///
    /// Split out of the `onChange` it used to live inside: the closure had
    /// grown past what the type checker would swallow in one expression.
    private func rearmSchedules() {
        let blocks = self.blocks
        let wantsAlarm = prefs.gateMode == .alarm
        // Only the blocks with something to ask can ring.
        let ringable = store.activeBlocks()
        let owed = store.unwrittenBlockIDs()
        Task { await ReminderService.shared.reschedule(for: blocks) }
        Task {
            await AlarmService.shared.reschedule(
                for: ringable,
                enabled: wantsAlarm,
                owed: owed
            )
        }
    }

    /// A card, and — in edit mode — the control that removes it.
    ///
    /// Hand-rolled rather than a `List`'s own edit control, which is welded to
    /// the leading edge and can't be moved. An `HStack` puts the minus on the
    /// trailing side instead, and centres it on the card by default alignment
    /// however tall that card grows.
    private func blockRow(_ block: JournalBlock) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Button {
                opened = block
            } label: {
                BlockCard(
                    block: block,
                    prompts: prompts.filter { $0.blockID == block.id },
                    isEditing: isEditing
                )
            }
            .buttonStyle(.plain)
            // Edit mode is for removing blocks, not entering them — the same
            // reason the chevron goes while it's on. Hit testing rather than
            // `disabled`, which greys the card's contents out as though the
            // block itself were unavailable.
            .allowsHitTesting(!isEditing)

            if isEditing {
                Button {
                    Haptics.tap(.light)
                    pendingDelete = block
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 25))
                        // Palette rendering so the bar reads white on red
                        // rather than punching a hole through to the sky.
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.Palette.canvas, Theme.Palette.danger)
                        .frame(
                            width: Theme.Space.tapTarget,
                            height: Theme.Space.tapTarget
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Grows out of nothing on the trailing edge, rather than
                // appearing fully formed the instant Edit is pressed.
                .transition(
                    .scale(scale: 0.4, anchor: .trailing).combined(with: .opacity)
                )
                .accessibilityLabel("Delete \(block.timeLabel)")
            }
        }
    }

    /// Refused for the last block standing — the one rule this screen
    /// enforces, and the reason `deleteBlock` reports a result at all.
    private func delete(_ block: JournalBlock) {
        if store.deleteBlock(block) {
            Haptics.success()
        } else {
            refusedDelete = true
            Haptics.warning()
        }
    }

    private var intro: some View {
        Text("Your prompts, grouped by when you answer them. Add as many times of day as you like.")
            .font(Theme.Typography.sans(14))
            .foregroundStyle(Theme.Palette.inkSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Changes worth rescheduling notifications for, and nothing else — a
    /// renamed block or a reworded prompt shouldn't churn the whole schedule.
    private var reminderFingerprint: String {
        blocks.map { "\($0.id)-\($0.hour):\($0.minute)-\($0.remindersEnabled)" }.joined()
    }
}

// MARK: - One block

/// A block at a glance: when it is, what it's called, and what it asks.
private struct BlockCard: View {
    let block: JournalBlock
    let prompts: [JournalPrompt]
    /// Hides the chevron while the list is being edited: nothing is navigating
    /// anywhere, so an arrow pointing onwards is a promise the card isn't
    /// keeping.
    var isEditing = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .center, spacing: Theme.Space.sm) {
                    // The time is the block's whole identity now, so it reads
                    // as the heading it has become rather than as a chip
                    // labelling a name beside it.
                    Text(block.timeLabel)
                        .font(Theme.Typography.serif(20))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)

                    Spacer(minLength: Theme.Space.xs)

                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                            .transition(.opacity)
                    }
                }

                if enabled.isEmpty {
                    Text("No prompts yet")
                        .font(Theme.Typography.sans(13))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(enabled) { prompt in
                            Text(prompt.title)
                                .font(Theme.Typography.serif(16))
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this block")
    }

    private var enabled: [JournalPrompt] {
        prompts.filter(\.isEnabled)
    }
}
