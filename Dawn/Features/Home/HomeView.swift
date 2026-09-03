import SwiftUI
import SwiftData

/// The day's page, once it's earned. Shows what you wrote this morning and
/// offers the evening reflection when it's time.
struct HomeView: View {
    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs

    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
    @State private var showEvening = false

    /// Three tiles side by side stop fitting around the first accessibility
    /// size; past that they stack.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var phase: DayPhase { DayPhase.current() }

    private var today: JournalEntry? {
        entries.first { Calendar.current.isDateInToday($0.day) }
    }

    private var eveningPrompts: [JournalPrompt] {
        store.prompts(for: .evening)
    }

    var body: some View {
        NavigationStack {
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        masthead
                        statsRow

                        if let today {
                            morningRecap(today)
                        }

                        if prefs.eveningPromptsEnabled && !eveningPrompts.isEmpty {
                            eveningSection
                        }

                        Color.clear.frame(height: Theme.Space.xxl)
                    }
                    .pageGutter()
                    .padding(.top, Theme.Space.sm)
                    // A vertical ScrollView lets content exceed its own width.
                    // At accessibility sizes the long date eyebrow did exactly
                    // that and dragged every sibling off both edges. Pinning to
                    // the viewport makes the text wrap instead.
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            // The sky is a backdrop, not a sibling. As a ZStack layer its
            // `ignoresSafeArea` grew the stack past the screen, and at
            // accessibility sizes the scroll content was laid out against that
            // larger box and hung off the left edge.
            .background { SkyBackground(phase: phase, intensity: 0.75) }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showEvening) {
                JournalSessionView(
                    session: JournalSession(
                        session: .evening,
                        prompts: eveningPrompts,
                        existing: today
                    ),
                    isDismissable: true,
                    onFinish: { showEvening = false }
                )
            }
        }
    }

    // MARK: - Pieces

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .eyebrowStyle()
            Text("\(phase.greeting)\(prefs.greetingName).")
                .font(Theme.Typography.serif(34))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.Space.xs)
    }

    private var statsRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Space.sm))

        return GlassEffectContainer(spacing: 14) {
            layout {
                StatTile(value: "\(store.currentStreak())", label: "day streak", symbol: "flame")
                StatTile(value: "\(store.totalCompletedMornings)", label: "mornings", symbol: "checkmark.seal")
                StatTile(
                    value: today?.mood.flatMap { Mood(rawValue: $0)?.label } ?? "—",
                    label: "arrived",
                    symbol: today?.mood.flatMap { Mood(rawValue: $0)?.symbol } ?? "circle.dotted"
                )
            }
        }
    }

    private func morningRecap(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeading(eyebrow: "This morning", title: "What you wrote")

            ForEach(entry.answers(for: .morning)) { answer in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(answer.promptTitle)
                            .font(Theme.Typography.sans(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkTertiary)

                        ForEach(Array(answer.filledLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.Typography.serif(17))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var eveningSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeading(eyebrow: "Later", title: "Evening reflection")

            if let today, today.isEveningComplete {
                ForEach(today.answers(for: .evening)) { answer in
                    GlassCard(tint: Theme.Palette.ink.opacity(0.05)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(answer.promptTitle)
                                .font(Theme.Typography.sans(12, weight: .medium))
                                .foregroundStyle(Theme.Palette.inkTertiary)
                            ForEach(Array(answer.filledLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(Theme.Typography.serif(17))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        Text("Close the day when you're ready.")
                            .font(Theme.Typography.serif(19))
                            .foregroundStyle(Theme.Palette.ink)
                        GhostButton(
                            title: "Begin reflection",
                            systemImage: "moon.stars",
                            isNested: true
                        ) {
                            showEvening = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.ember)
            // A long mood name ("Luminous") would otherwise wrap and make this
            // tile taller than its neighbours. At normal sizes it shrinks to
            // one line instead; at accessibility sizes wrapping wins.
            Text(value)
                .font(Theme.Typography.sans(20, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            // No lineLimit: at accessibility sizes "day streak" has to wrap
            // rather than truncate to "y st…".
            Text(label)
                .font(Theme.Typography.sans(11))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // maxHeight so every tile in the row matches the tallest one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .glassEffect(
            .regular.tint(Theme.Palette.emberSoft.opacity(0.18)),
            in: .rect(cornerRadius: 20)
        )
        // One element, read as "6, day streak" rather than three fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}
