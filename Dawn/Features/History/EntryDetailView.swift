import SwiftUI

/// One day, read back. Typeset like a page rather than a record.
struct EntryDetailView: View {
    let entry: JournalEntry

    var body: some View {
        ZStack {
            SkyBackground(phase: DayPhase.current(), intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(entry.day.formatted(.dateTime.weekday(.wide)))
                            .eyebrowStyle()
                        Text(entry.day.formatted(.dateTime.day().month(.wide).year()))
                            .font(Theme.Typography.serif(30))
                            .foregroundStyle(Theme.Palette.ink)
                        if let mood = entry.mood.flatMap({ Mood(rawValue: $0) }) {
                            HStack(spacing: 6) {
                                Image(systemName: mood.symbol)
                                    .font(.system(size: 12))
                                Text("Arrived \(mood.label.lowercased())")
                                    .font(Theme.Typography.sans(13))
                            }
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .padding(.top, 2)
                        }
                    }

                    section(title: "Morning", answers: entry.answers(for: .morning))
                    section(title: "Evening", answers: entry.answers(for: .evening))

                    Color.clear.frame(height: Theme.Space.lg)
                }
                .pageGutter()
                .padding(.top, Theme.Space.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(entry.day.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
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
