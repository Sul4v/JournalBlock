import SwiftUI

/// One day, read back. Typeset like a page rather than a record.
struct EntryDetailView: View {
    @Environment(\.journalStore) private var store
    @Environment(BackupController.self) private var backup
    @Environment(\.dismiss) private var dismiss

    let entry: JournalEntry

    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text(entry.day.formatted(.dateTime.day().month(.wide).year()))
                        .font(Theme.Typography.serif(30))
                        .foregroundStyle(Theme.Palette.ink)

                    ForEach(entry.answersByBlock, id: \.blockID) { group in
                        section(title: group.title, answers: group.answers)
                    }

                    Color.clear.frame(height: Theme.Space.lg)
                }
                .pageGutter()
                .padding(.top, Theme.Space.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(entry.day.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                } label: {
                    // Bare glyph, as in `BlockDetailView`: iOS draws its own
                    // round glass button behind a toolbar item, and the circled
                    // symbol would put a second ring inside the first.
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                }
                .accessibilityLabel("Entry options")
            }
        }
        // An alert rather than a confirmation dialog, for the reason spelled
        // out in `BlockDetailView`: raised from a toolbar menu, the dialog
        // anchors itself to the navigation bar and covers the title.
        .alert("Delete this entry?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteWarning)
        }
    }

    /// Says the two things the user can't see: that the backed-up copy goes
    /// too, and — on today — that the day becomes unwritten again, which means
    /// a gating block will ask for it back.
    private var deleteWarning: String {
        let base = "What you wrote that day is erased on this device and removed from your backup. This can't be undone."
        guard Calendar.current.isDateInToday(entry.day) else { return base }
        return base + " Today counts as unwritten afterwards, so any block that locks your phone will ask for it again."
    }

    private func delete() {
        let day = store.deleteEntry(entry)
        backup.forget(day: day)
        Haptics.success()
        // Pop first: this screen is bound to an entry that no longer exists.
        dismiss()
    }

    @ViewBuilder
    private func section(title: String, answers: [PromptAnswer]) -> some View {
        let filled = answers.filter(\.hasContent)
        if !filled.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(title).eyebrowStyle(Theme.Palette.emberDeep)

                ForEach(filled) { answer in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(answer.promptTitle)
                            .font(Theme.Typography.sans(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkTertiary)

                        ForEach(Array(answer.filledLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.Typography.serif(19))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.bottom, Theme.Space.xs)
                }
            }
        }
    }
}
