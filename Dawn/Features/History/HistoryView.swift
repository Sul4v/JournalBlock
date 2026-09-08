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
                        LazyVStack(alignment: .leading, spacing: Theme.Space.lg) {
                            masthead

                            ForEach(months, id: \.start) { month in
                                monthSection(month)
                            }

                            Color.clear.frame(height: Theme.Space.xxl)
                        }
                        .pageGutter()
                        .padding(.top, Theme.Space.sm)
                    }
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .softTopEdge()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Matches the Home masthead so the app keeps one typographic voice
    /// instead of borrowing UIKit's bold sans large title.
    private var masthead: some View {
        // Title left, count right — the same masthead shape Today uses for its
        // date and streak, so the two tabs open the same way.
        HStack(alignment: .center, spacing: Theme.Space.md) {
            Text("Entries")
                .font(Theme.Typography.serif(34))
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text(tally)
                .font(Theme.Typography.sans(14))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .fixedSize()
        }
    }

    /// "17 days". One number, because a day is an entry is a page — every row
    /// in this list is all three, and a second figure counting the same thing
    /// under a different name would only invite the reader to look for the
    /// difference.
    private var tally: String {
        let days = written.count
        return "\(days) \(days == 1 ? "day" : "days")"
    }

    // MARK: - Months

    /// The written days, bucketed by month, newest first.
    ///
    /// A flat list of dates gave every day its own glass card holding two
    /// words, which made a month of writing look like a column of empty
    /// containers. Grouping gives the page a rhythm and lets each row drop the
    /// month it repeats — a day inside "September" only has to say "8".
    private var months: [(start: Date, label: String, entries: [JournalEntry])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [JournalEntry]] = [:]

        for entry in written {
            let start = calendar.dateInterval(of: .month, for: entry.day)?.start
                ?? entry.day
            if buckets[start] == nil { order.append(start) }
            buckets[start, default: []].append(entry)
        }

        return order.map { start in
            (start, monthLabel(start), buckets[start] ?? [])
        }
    }

    /// The year only when it isn't this one, so a recent month stays short and
    /// one from two Septembers ago is still unambiguous.
    private func monthLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: .now)
        return isThisYear
            ? date.formatted(.dateTime.month(.wide))
            : date.formatted(.dateTime.month(.wide).year())
    }

    private func monthSection(
        _ month: (start: Date, label: String, entries: [JournalEntry])
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.label).eyebrowStyle(Theme.Palette.emberDeep)
                Spacer(minLength: Theme.Space.sm)
                Text("\(month.entries.count)")
                    .font(Theme.Typography.sans(12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
            .padding(.bottom, Theme.Space.sm)

            ForEach(Array(month.entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink {
                    EntryDetailView(entry: entry)
                } label: {
                    EntryRow(entry: entry)
                }
                .buttonStyle(.plain)

                // Hairlines between days rather than a card around each. Nine
                // rounded rectangles holding one date apiece read as packaging;
                // a ruled column reads as an index.
                if index < month.entries.count - 1 {
                    Rectangle()
                        .fill(Theme.Palette.rule)
                        .frame(height: 1)
                }
            }
        }
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            // The day, big enough to scan down the column, with the weekday
            // beside it — which is the thing you actually remember a day by.
            Text(entry.day.formatted(.dateTime.day()))
                .font(Theme.Typography.serif(22))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
                .frame(minWidth: 30, alignment: .leading)

            Text(entry.day.formatted(.dateTime.weekday(.wide)))
                .font(Theme.Typography.sans(15))
                .foregroundStyle(Theme.Palette.inkSecondary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkTertiary)
        }
        .padding(.vertical, Theme.Space.sm)
        .frame(minHeight: Theme.Space.tapTarget)
        .contentShape(Rectangle())
        // One row, one VoiceOver element — not three fragments.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
