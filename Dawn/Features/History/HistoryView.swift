import SwiftUI
import SwiftData

/// Past pages. Deliberately quiet — a list of days, not a dashboard.
struct HistoryView: View {
    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]

    private var written: [JournalEntry] {
        entries.filter { !$0.allLines.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(phase: DayPhase.current(), intensity: 0.6)

                if written.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Space.sm) {
                            masthead
                                .padding(.bottom, Theme.Space.xs)

                            ForEach(written) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    EntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                            Color.clear.frame(height: Theme.Space.xxl)
                        }
                        .pageGutter()
                        .padding(.top, Theme.Space.sm)
                    }
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Matches the Home masthead so the app keeps one typographic voice
    /// instead of borrowing UIKit's bold sans large title.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(written.count) day\(written.count == 1 ? "" : "s") written")
                .eyebrowStyle()
            Text("Entries")
                .font(Theme.Typography.serif(34))
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "book.closed")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Theme.Palette.inkTertiary)
            Text("Nothing here yet")
                .font(Theme.Typography.serif(22))
                .foregroundStyle(Theme.Palette.ink)
            Text("Tomorrow's pages will land here.")
                .font(Theme.Typography.sans(14))
                .foregroundStyle(Theme.Palette.inkTertiary)
        }
    }
}

private struct EntryRow: View {
    let entry: JournalEntry

    private var preview: String {
        entry.allLines.first ?? ""
    }

    var body: some View {
        GlassCard(padding: Theme.Space.md) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                VStack(spacing: 1) {
                    Text(entry.day.formatted(.dateTime.day()))
                        .font(Theme.Typography.sans(22, weight: .light))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(entry.day.formatted(.dateTime.month(.abbreviated)))
                        .font(Theme.Typography.sans(10, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                        .textCase(.uppercase)
                }
                .frame(minWidth: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(preview)
                        .font(Theme.Typography.serif(16))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if entry.isMorningComplete {
                            Badge(symbol: "sun.horizon", text: "Morning")
                        }
                        if entry.isEveningComplete {
                            Badge(symbol: "moon.stars", text: "Evening")
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .padding(.top, 4)
            }
        }
        // One row, one VoiceOver element — not four fragments.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct Badge: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(Theme.Typography.sans(10, weight: .medium))
        }
        .foregroundStyle(Theme.Palette.inkSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Palette.ink.opacity(0.05)))
    }
}
