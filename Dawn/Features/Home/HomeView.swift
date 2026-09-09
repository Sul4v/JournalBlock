import SwiftUI
import SwiftData

/// Tomorrow's prepared page after signup, then the day itself — one section
/// per block the user has set up, in the order the day runs.
struct HomeView: View {
    var isPreparingFirstMorning = false

    @Environment(\.journalStore) private var store
    @Environment(Preferences.self) private var prefs

    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \JournalPrompt.order) private var prompts: [JournalPrompt]
    @Query(
        sort: [
            SortDescriptor(\JournalBlock.hour),
            SortDescriptor(\JournalBlock.minute),
            SortDescriptor(\JournalBlock.order)
        ]
    ) private var blocks: [JournalBlock]
    /// The block being written right now, if any.
    @State private var writing: JournalBlock?
    /// Raised for one slow breath to point at the block that is owed. Not a
    /// permanent state of the card: a halo that never goes out stops being a
    /// signal and becomes decoration, and this screen has to be liveable on a
    /// morning when the page simply isn't written yet.
    @State private var isNudgingDueBlock = false
    /// Drives the masthead date. See `masthead`.
    @State private var day = Date.now
    /// Ticks every minute so a block that comes due while the screen is open
    /// starts saying so then, rather than at the next launch.
    @State private var clock = Date.now

    private var phase: DayPhase { DayPhase.current() }

    private var today: JournalEntry? {
        entries.first { Calendar.current.isDateInToday($0.day) }
    }

    /// Only blocks with something to answer. An empty block is a shape the user
    /// is still building in Settings, not a thing to put in front of them here.
    private var activeBlocks: [JournalBlock] {
        blocks.filter { block in
            prompts.contains { $0.blockID == block.id && $0.isEnabled }
        }
    }

    private func page(for block: JournalBlock) -> [JournalPrompt] {
        prompts.filter { $0.blockID == block.id && $0.isEnabled }
    }

    /// Where a block stands right now. The app no longer opens onto the writing
    /// flow, so this label is the only thing telling the user a sitting is
    /// still owed — it has to say so plainly rather than leave them to infer it
    /// from the dots.
    private enum BlockStatus {
        case done
        /// Its hour has passed and it hasn't been answered.
        case owed
        /// Still ahead in the day.
        case upcoming
    }

    /// Brings the owed block into view — and no further.
    ///
    /// Deliberately no anchor. With `.top` the scroll drove the block to the
    /// very top of the viewport whether it needed to move or not, which shoved
    /// the date under the status bar on a day that already fitted on screen and
    /// read as a glitch. A nil anchor scrolls the minimum needed to make the
    /// block visible, so a day you can already see doesn't move at all.
    ///
    /// The order is never touched. The times are the spine of this screen; a
    /// 9:00 PM card above a 7:00 AM one would read as a bug.
    private func revealDueBlock(with proxy: ScrollViewProxy, animated: Bool) {
        guard let dueBlockID else { return }

        // A beat, so the scroll happens after the list has been laid out —
        // without it `scrollTo` lands on a view whose height is still zero.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(Theme.Motion.settle) { proxy.scrollTo(dueBlockID) }
            } else {
                proxy.scrollTo(dueBlockID)
            }
        }
    }

    /// One breath of emphasis on the owed card: a slight lift, and nothing
    /// else. An ember halo lived here too and read as decoration rather than
    /// as a signal.
    ///
    /// Called on arrival, not on a timer, because its job is to answer the
    /// question someone carries in from the shield: *which one?* Once that is
    /// answered the card has nothing more to say, so the glow leaves rather
    /// than pulsing on while they read.
    ///
    /// Silent under Reduce Motion. The card is already scrolled to the top of
    /// the screen and already carries the ember dot, so nothing is lost by
    /// skipping this — which is the test for whether motion was load-bearing.
    private func nudgeDueBlock() {
        guard dueBlockID != nil, !Theme.A11y.wantsLessMotion else { return }

        // After `revealDueBlock`'s scroll, or the glow rises on a card that is
        // still travelling up the screen and reads as a rendering artefact.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.5)) { isNudgingDueBlock = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 1.0)) { isNudgingDueBlock = false }
            }
        }
    }

    /// The block the day is actually waiting on: the earliest one that has come
    /// due and still isn't written.
    ///
    /// Distinct from `.owed`, which is true of every block whose hour has
    /// passed. On a day where breakfast and lunch were both missed, all of them
    /// are owed but only one of them is the next thing to do — and that is the
    /// one Today opens on and the one that gets the badge.
    private var dueBlockID: UUID? {
        activeBlocks.first { status(for: $0, at: clock) == .owed }?.id
    }

    /// Read off the clock, not off `store.pendingGateBlock`. That resolves the
    /// single block holding the lock; here every unanswered block that has come
    /// due says so, because the user asked to see the state of each one.
    private func status(for block: JournalBlock, at now: Date) -> BlockStatus {
        if today?.isComplete(block.id) == true { return .done }
        let minutes = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)
        return minutes >= block.minutesOfDay ? .owed : .upcoming
    }



    var body: some View {
        NavigationStack {
            Group {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.lg) {
                            masthead

                            if isPreparingFirstMorning {
                                tomorrowPreview
                            } else if activeBlocks.isEmpty {
                                emptyDay
                            } else {
                                ForEach(activeBlocks) { block in
                                    blockSection(block)
                                        .id(block.id)
                                }
                            }

                            Color.clear.frame(height: Theme.Space.xxl)
                        }
                        .pageGutter()
                        .padding(.top, Theme.Space.sm)
                        // Keep content within the viewport at accessibility sizes.
                        .containerRelativeFrame(.horizontal, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .softTopEdge()
                    .onAppear {
                        revealDueBlock(with: proxy, animated: false)
                        nudgeDueBlock()
                    }
                    .onChange(of: dueBlockID) { _, _ in
                        revealDueBlock(with: proxy, animated: true)
                    }
                    // Arriving from the shield or the alarm while Today was
                    // already the visible tab fires no `onAppear`, which is
                    // exactly the case this hand-off exists to serve.
                    .onReceive(NotificationCenter.default.publisher(for: .dawnBlockHandoff)) { _ in
                        revealDueBlock(with: proxy, animated: true)
                        nudgeDueBlock()
                    }
                }
            }
            // The sky is a backdrop, not a sibling. As a ZStack layer its
            // `ignoresSafeArea` grew the stack past the screen, and at
            // accessibility sizes the scroll content was laid out against that
            // larger box and hung off the left edge.
            .background { SkyBackground(phase: phase, intensity: 0.75) }
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                day = .now
                clock = .now
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                clock = now
            }
            .fullScreenCover(item: $writing) { block in
                JournalSessionView(
                    session: JournalSession(
                        block: block,
                        prompts: page(for: block),
                        existing: today
                    ),
                    isDismissable: true,
                    onFinish: { writing = nil }
                )
            }
        }
    }

    // MARK: - Pieces

    private var masthead: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            // "September 1" in the user's locale — `.month(.wide).day()` puts
            // the two in the right order and language, which "MMMM d" would
            // not. Held in state and refreshed on the day change, because a
            // phone left open overnight would otherwise still say yesterday.
            Text(day.formatted(.dateTime.month(.wide).day()))
                .font(Theme.Typography.serif(34))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            streakCounter
        }
        .padding(.bottom, Theme.Space.xs)
    }

    private var streakCounter: some View {
        let streak = store.currentStreak()

        return HStack(spacing: Theme.Space.xs) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .foregroundStyle(streak > 0 ? Theme.Palette.ember : Theme.Palette.inkTertiary)
            if streak > 0 {
                Text("\(streak)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .font(Theme.Typography.sans(20, weight: .medium))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day streak")
        .accessibilityValue(streak > 0 ? (streak == 1 ? "1 day" : "\(streak) days") : "No active streak")
    }

    /// The first-run screen: every sitting the user set up, with the questions
    /// they will answer tomorrow.
    ///
    /// Shows all of them rather than only the one holding the lock. Someone who
    /// just set an evening time and then found no evening on this screen would
    /// reasonably conclude it hadn't taken.
    private var tomorrowPreview: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Your first pages are set. You'll answer these tomorrow.")
                .font(Theme.Typography.sans(16))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(activeBlocks) { block in
                previewSection(block)
            }

            NavigationLink {
                PromptLibraryView()
            } label: {
                Label("Edit prompts", systemImage: "slider.horizontal.3")
                    .font(Theme.Typography.sans(15, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(minHeight: Theme.Space.tapTarget)
            }
            .buttonStyle(.glass)
        }
    }

    private func previewSection(_ block: JournalBlock) -> some View {
        let page = self.page(for: block)

        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            // Exploratory: a block is its time, so the time is the heading and
            // the small grey one that used to trail the name is gone — two
            // labels for one fact. Names are untouched in the model.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                SectionHeading(title: block.timeLabel)
            }

            Text(PromptTemplate.duration(seconds: page.reduce(0) { $0 + $1.style.estimatedSeconds }))
                .font(Theme.Typography.sans(13))
                .foregroundStyle(Theme.Palette.inkTertiary)

            ForEach(Array(page.enumerated()), id: \.element.id) { index, prompt in
                GlassCard {
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Text(String(format: "%02d", index + 1))
                            .font(Theme.Typography.sans(12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.emberDeep)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(prompt.title)
                                .font(Theme.Typography.serif(20))
                                .foregroundStyle(Theme.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if !prompt.hint.isEmpty {
                                Text(prompt.hint)
                                    .font(Theme.Typography.sans(13))
                                    .foregroundStyle(Theme.Palette.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Every block the user has, as the questions it will ask, each carrying
    /// whether it has been answered yet.
    ///
    /// This replaces two things. The first was an invitation line — "A few
    /// lines before the day starts" — which was atmosphere where the user
    /// wanted to know what they were in for. The second was a full recap of
    /// everything written today, which turned Today into a reading screen; the
    /// day is still readable in full by reopening the block, and in Entries.
    ///
    /// The dots also do the job the warm card tint used to: a sitting still
    /// owed looks different from a finished one without colouring the card.
    private func blockSection(_ block: JournalBlock) -> some View {
        let page = page(for: block)
        let answered = Set(
            (today?.answers(forBlock: block.id) ?? [])
                .filter(\.hasContent)
                .map(\.promptID)
        )
        let isDone = today?.isComplete(block.id) == true
        let state = status(for: block, at: clock)
        let isNudged = block.id == dueBlockID && isNudgingDueBlock
        let written = Dictionary(
            (today?.answers(forBlock: block.id) ?? []).map { ($0.promptID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let isDueNow = block.id == dueBlockID

        return VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                SectionHeading(title: block.timeLabel)

                statusMarker(state, isDueNow: isDueNow)
            }

            // Every card carries the same surface. Tinting the due one warm
            // made the day look like two different screens stacked, and the
            // signal was already being carried twice over — the ember dot on
            // the time line, and the scroll that opens on this block.
            GlassCard(tint: Theme.Palette.ink.opacity(0.04)) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        ForEach(page.prefix(Self.maxPromptsShown)) { prompt in
                            promptBlock(prompt, answer: written[prompt.id])
                        }

                        if page.count > Self.maxPromptsShown {
                            Text("+\(page.count - Self.maxPromptsShown) more")
                                .font(Theme.Typography.sans(12, weight: .medium))
                                .foregroundStyle(Theme.Palette.inkTertiary)
                        }
                    }

                    // Bottom right, where the eye lands after reading the list
                    // — and, more to the point, off the left margin the dots
                    // hold, where the button read as a fourth question.
                    //
                    // A block can be re-opened all day. Someone who thought of
                    // a fourth thing at lunchtime shouldn't have to wait for
                    // tomorrow, so this is never absent — only relabelled.
                    HStack {
                        Spacer(minLength: 0)

                        // Just the chevron, no disc around it. "Add to
                        // this", "Keep writing" and "Begin" were three labels
                        // for one destination, and the card already says
                        // which of them applies: the
                        // dots show what's answered and the marker above says
                        // whether it's still owed. The words survive as the
                        // accessibility label, where they're the only clue.
                        IconButton(
                            systemName: "chevron.right",
                            accessibilityTitle: buttonTitle(
                                isDone: isDone,
                                hasAnswers: !answered.isEmpty
                            ),
                            size: 17,
                            isGlass: false,
                            tint: Theme.Palette.emberDeep
                        ) {
                            writing = block
                        }
                    }
                }
            }
        }
        // Scale rather than offset: a card that moves shifts everything under
        // it, and on a day with three blocks that reads as the list twitching.
        .scaleEffect(isNudged ? 1.018 : 1.0, anchor: .center)
    }

    /// Sits between the block's name and its time, so it reads as one line:
    /// "Morning · Still to write · 7:00".
    ///
    /// The right-hand end of a block's time line.
    ///
    /// Three states, three marks, and one silence. The block that is *due* —
    /// the earliest one still unwritten — gets a dot, and nothing else on this
    /// screen does; a mark with one meaning needs no label. A block that came
    /// due earlier and was skipped past keeps the words instead, so the two
    /// owed states can't be confused for each other. A finished block gets a
    /// tick, in ink rather than ember: done is worth seeing, but it is not the
    /// thing being asked for, and an ember tick would compete with the one mark
    /// that is. Only a block whose hour hasn't come says nothing at all — it
    /// has nothing to report yet, and filling every row would leave the dot
    /// with nothing to stand out against.
    @ViewBuilder
    private func statusMarker(_ state: BlockStatus, isDueNow: Bool) -> some View {
        switch state {
        case .owed where isDueNow:
            Circle()
                .fill(Theme.Palette.ember)
                .frame(width: 9, height: 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Due now")

        case .owed:
            Text("Still to write")
                .font(Theme.Typography.sans(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.ember)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Still to write")

        case .done:
            Image(systemName: "checkmark")
                .font(Theme.Typography.sans(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkTertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Written")

        case .upcoming:
            EmptyView()
        }
    }

    /// The most prompts a card will show before it stops counting them out.
    ///
    /// Six keeps the tallest card inside a phone screen. Past that the card
    /// stops being a glance and starts being the page itself, which is what
    /// the block screen is for.
    private static let maxPromptsShown = 6

    /// One prompt, one line, one voice.
    ///
    /// Written, it shows what was written. Unwritten, it shows what will be
    /// asked, a shade lighter. Never both — pairing a grey question with a
    /// serif answer meant a four-prompt card was eight runs of text in two
    /// typefaces, every other one ending in an ellipsis, and it read as noise
    /// however calm each part was on its own.
    ///
    /// Only the first answer shows. Joining them with a separator was honest
    /// about how much had been written and put an ellipsis on every line to do
    /// it; on a screen whose job is the shape of the day, one clean line beats
    /// three truncated ones. The whole page is one tap away.
    private func promptBlock(_ prompt: JournalPrompt, answer: PromptAnswer?) -> some View {
        let written = (answer?.filledLines.first ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmed
        let hasWriting = !written.isEmpty

        return Text(hasWriting ? written : prompt.title)
            .font(Theme.Typography.serif(18))
            .foregroundStyle(hasWriting ? Theme.Palette.ink : Theme.Palette.inkSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(prompt.title)
            .accessibilityValue(hasWriting ? written : "Not answered yet")
    }

    private func buttonTitle(isDone: Bool, hasAnswers: Bool) -> String {
        if isDone { return "Add to this" }
        return hasAnswers ? "Keep writing" : "Begin"
    }

    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeading(title: "Nothing scheduled")

            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("You've switched off every prompt. Add a time and a question, and it appears here.")
                        .font(Theme.Typography.serif(19))
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        PromptLibraryView()
                    } label: {
                        Label("Set up your prompts", systemImage: "slider.horizontal.3")
                            .font(Theme.Typography.sans(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .padding(.horizontal, Theme.Space.md)
                            .frame(minHeight: Theme.Space.tapTarget)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
