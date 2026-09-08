import Foundation
import SwiftData

/// All reads and writes of journal data go through here, so the rules about
/// "one entry per day" and streak counting live in exactly one place.
@MainActor
final class JournalStore {
    private let context: ModelContext
    private let calendar: Calendar
    /// Read for the wake time the first block inherits, and written back when
    /// that block is retimed so the AlarmKit wake alarm follows it.
    private let prefs: Preferences

    init(
        context: ModelContext,
        calendar: Calendar = .current,
        prefs: Preferences = .shared
    ) {
        self.context = context
        self.calendar = calendar
        self.prefs = prefs
    }

    // MARK: - Library setup

    /// Everything the prompt library needs on launch, in the order it needs it.
    /// One call site so the three steps can never run out of order.
    func prepareLibrary() {
        seedPromptsIfNeeded()
        migratePromptOriginsIfNeeded()
        migrateToBlocksIfNeeded()
        repairLibraryIfNeeded()
    }

    /// Installs a starting page on first launch.
    ///
    /// A fresh install gets the classic set; onboarding replaces it a few
    /// screens later with the page the quiz recommends. This exists so an
    /// install that reaches the journal without passing through the quiz — a
    /// debug launch, a restored account — still has something to ask.
    func seedPromptsIfNeeded() {
        let existing = (try? context.fetchCount(FetchDescriptor<JournalPrompt>())) ?? 0
        guard existing == 0 else { return }
        for prompt in JournalPrompt.defaultSet() { context.insert(prompt) }
        try? context.save()
    }

    /// Backfills role and provenance onto prompts written before templates
    /// existed, matching on the exact wording the old default set shipped with.
    /// Anything else was written by the user and stays roleless, which is
    /// correct — an open prompt is a real role, not a missing one.
    private func migratePromptOriginsIfNeeded() {
        let stale = allPrompts().filter { $0.isBuiltIn && $0.originKey.isEmpty }
        guard !stale.isEmpty else { return }

        for prompt in stale {
            guard let key = Self.legacyOriginKeys[prompt.title],
                  let role = PromptRole.owning(key)
            else {
                // A reworded built-in. Keep the user's words; it just loses the
                // "reset wording" affordance, which is better than silently
                // overwriting what they wrote.
                prompt.originTemplateID = PromptTemplate.classicFive.id
                continue
            }
            prompt.role = role
            prompt.originTemplateID = PromptTemplate.classicFive.id
            prompt.originKey = key
        }
        try? context.save()
    }

    /// The wording the pre-template default set shipped with.
    private static let legacyOriginKeys: [String: String] = [
        "I am grateful for…": "gratitude.three",
        "What would make today great?": "intention.good-day",
        "Daily affirmation. I am…": "affirmation.today-i-am",
        "Three amazing things that happened today…": "reflection.went-well",
        "How could I have made today even better?": "improvement.differently"
    ]

    /// Puts a library that can't be journaled back into a usable state.
    ///
    /// Three things are healed, in this order: a day with no blocks at all, a
    /// prompt whose block no longer exists, and a gating block with nothing
    /// enabled in it. That last one is the dangerous case — `JournalSession`
    /// reads an empty page as "already finished", so the gate lifts with
    /// nothing written and the entire premise of the app is off. The guards in
    /// the editing methods stop it happening now; this heals installs and
    /// restored backups that already got there.
    func repairLibraryIfNeeded() {
        var blocks = self.blocks()

        if blocks.isEmpty {
            let block = JournalBlock(
                title: JournalBlock.defaultTitle(forHour: prefs.wakeHour),
                hour: prefs.wakeHour,
                minute: prefs.wakeMinute,
                gatesDay: true,
                legacySession: .morning
            )
            context.insert(block)
            blocks = [block]
        }

        // Re-file anything orphaned by a deleted block rather than dropping it:
        // an orphan is invisible in every screen but still in the database, and
        // a prompt someone wrote is not ours to bin.
        let known = Set(blocks.map(\.id))
        let fallback = blocks[0]
        for prompt in allPrompts() where !known.contains(prompt.blockID) {
            prompt.blockID = fallback.id
        }

        for block in blocks {
            let page = prompts(for: block, enabledOnly: false)
            if page.isEmpty {
                // A gate with no questions can't be answered, so it can't be a
                // gate. Better than reseeding prompts the user deleted.
                block.gatesDay = false
            } else {
                if !page.contains(where: \.isEnabled) { page[0].isEnabled = true }
                // Every answerable block locks and reminds. This is also the
                // migration: blocks made before that was true, with either
                // switch left off, are brought into line on the next launch.
                block.gatesDay = true
                block.remindersEnabled = true
            }
        }

        renumber()
    }

    // MARK: - Migrating to blocks

    /// Turns the old fixed morning/evening pair into two real blocks.
    ///
    /// Runs once, on the first launch after the update. Everything the user had
    /// is carried across: their wake time becomes the morning block's time, the
    /// morning keeps the gate, and `eveningPromptsEnabled == false` is preserved
    /// by switching that block's prompts off rather than by dropping the block —
    /// which keeps a page they wrote one toggle away instead of deleting it.
    private func migrateToBlocksIfNeeded() {
        guard blocks().isEmpty else { return }

        let morning = JournalBlock(
            title: "Morning",
            hour: prefs.wakeHour,
            minute: prefs.wakeMinute,
            order: 0,
            gatesDay: true,
            legacySession: .morning
        )
        context.insert(morning)

        var eveningID: UUID?
        let eveningPrompts = allPrompts().filter { $0.session == .evening }
        if !eveningPrompts.isEmpty {
            let evening = JournalBlock(
                title: "Evening",
                hour: 21,
                order: 1,
                legacySession: .evening
            )
            context.insert(evening)
            eveningID = evening.id

            if !prefs.eveningPromptsEnabled {
                for prompt in eveningPrompts { prompt.isEnabled = false }
            }
        }

        for prompt in allPrompts() {
            prompt.blockID = prompt.session == .evening ? (eveningID ?? morning.id) : morning.id
        }

        // Days already written predate `completions`, and the streak now counts
        // those. Backfill from the two timestamps they do carry.
        for entry in allEntries() {
            if let at = entry.morningCompletedAt { entry.markComplete(morning.id, at: at) }
            if let at = entry.eveningCompletedAt, let eveningID {
                entry.markComplete(eveningID, at: at)
            }
            for answer in entry.answers where answer.blockTitle.isEmpty {
                let isEvening = answer.session == .evening
                answer.blockID = isEvening ? (eveningID ?? morning.id) : morning.id
                answer.blockTitle = isEvening ? "Evening" : "Morning"
            }
        }

        try? context.save()
    }

    // MARK: - Reading blocks

    /// Every block, in the order the day runs. Time is the sort key rather than
    /// `order`, so a block moved to 6am reads first without renumbering the
    /// rest; `order` only settles two blocks at the same minute.
    func blocks() -> [JournalBlock] {
        let all = (try? context.fetch(FetchDescriptor<JournalBlock>())) ?? []
        return all.sorted {
            ($0.minutesOfDay, $0.order) < ($1.minutesOfDay, $1.order)
        }
    }

    func block(id: UUID) -> JournalBlock? {
        blocks().first { $0.id == id }
    }

    /// The blocks worth showing on Today: the ones with something to answer.
    func activeBlocks() -> [JournalBlock] {
        blocks().filter { !prompts(for: $0).isEmpty }
    }

    // MARK: - Editing blocks

    /// Where a new block is *proposed*: an hour after the last one, wrapping
    /// rather than running past midnight.
    ///
    /// A suggestion, which is why it returns components instead of inserting
    /// anything. Its predecessor inserted and saved a named block the instant
    /// the plus was tapped, so backing out of the screen that followed left a
    /// half-made sitting in the user's list — one they never agreed to and had
    /// to go and delete. `NewBlockView` puts these values on a wheel instead
    /// and writes nothing until the user commits.
    func nextBlockSlot() -> (hour: Int, minute: Int) {
        let last = blocks().last
        let minutes = ((last?.minutesOfDay ?? (prefs.wakeHour * 60 - 60)) + 60) % (24 * 60)
        return (minutes / 60, minutes % 60)
    }

    /// Creates a block and the questions it opens with, as one act.
    ///
    /// Both halves or neither: a block with no prompts is filtered out of
    /// `activeBlocks()`, can't hold the gate, and shows the user a sitting on
    /// their settings screen that will never appear on their Today screen. The
    /// creation flow refuses to commit without a question for that reason, and
    /// this is the only door it comes through.
    ///
    @discardableResult
    func createBlock(
        hour: Int,
        minute: Int,
        prompts: [PromptDraft]
    ) -> JournalBlock {
        let block = JournalBlock(
            title: JournalBlock.defaultTitle(forHour: hour),
            hour: hour,
            minute: minute,
            order: (blocks().map(\.order).max() ?? -1) + 1
        )
        context.insert(block)
        for draft in prompts {
            _ = addPrompt(
                title: draft.title,
                hint: draft.hint,
                style: draft.style,
                role: draft.role,
                originKey: draft.originKey,
                to: block
            )
        }
        try? context.save()
        return block
    }

    /// Refused for the last block standing: a journal with nowhere to write is
    /// not a state the user can get back out of from this screen.
    @discardableResult
    func deleteBlock(_ block: JournalBlock) -> Bool {
        let remaining = blocks().filter { $0.id != block.id }
        guard !remaining.isEmpty else { return false }

        let wasGate = block.gatesDay
        for prompt in prompts(for: block, enabledOnly: false) { context.delete(prompt) }
        context.delete(block)

        // The lock passes to the next block rather than evaporating. Deleting a
        // sitting is a scheduling decision; giving up the locked front door is
        // a different one, and it has its own switch in the block's menu.
        if wasGate, let heir = remaining.first(where: { !prompts(for: $0).isEmpty }) {
            heir.gatesDay = true
        }

        renumber()
        syncWakeTime()
        return true
    }

    func setTime(hour: Int, minute: Int, on block: JournalBlock) {
        block.hour = hour
        block.minute = minute
        // The block is its time, so the vestigial `title` follows the hour
        // rather than going stale at whatever the block used to be called.
        block.title = JournalBlock.defaultTitle(forHour: hour)
        try? context.save()
        syncWakeTime()
    }

    /// Keeps `Preferences.wakeHour` — which is what the AlarmKit wake alarm and
    /// the onboarding copy read — pointed at the gating block. Without this the
    /// alarm would go on ringing at the time the block used to be at.
    func syncWakeTime() {
        guard let gate = blocks().first(where: \.gatesDay) ?? blocks().first else { return }
        guard prefs.wakeHour != gate.hour || prefs.wakeMinute != gate.minute else { return }
        prefs.wakeHour = gate.hour
        prefs.wakeMinute = gate.minute
    }

    // MARK: - The gate

    /// The block the user owes right now, or nil when the phone is theirs.
    ///
    /// The first gating block of the day is owed from midnight rather than from
    /// its own time: someone who set 7am and wakes at five would otherwise find
    /// the front door open, which is the one thing the app promises it won't be.
    /// Later blocks become due when they arrive.
    func pendingGateBlock(at date: Date = .now) -> JournalBlock? {
        pendingGateBlock(at: date, blocks: blocks(), entry: entry(on: date))
    }

    /// Pure given its inputs, so a view can hand over the blocks and entry it
    /// already observes and stay in step with them — a gate that only notices
    /// a finished session at the next launch is worse than no gate.
    func pendingGateBlock(
        at date: Date,
        blocks: [JournalBlock],
        entry: JournalEntry?
    ) -> JournalBlock? {
        let gating = blocks
            .filter { $0.gatesDay && !prompts(for: $0).isEmpty }
            .sorted { ($0.minutesOfDay, $0.order) < ($1.minutesOfDay, $1.order) }
        guard !gating.isEmpty else { return nil }

        let now = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)

        for (index, block) in gating.enumerated() {
            guard entry?.isComplete(block.id) != true else { continue }
            if index == 0 || now >= block.minutesOfDay { return block }
        }
        return nil
    }

    /// Every block today's page still owes: it has something to ask, and it
    /// hasn't been answered.
    ///
    /// What the alarm chain is built from. Broader than `pendingGateBlock`,
    /// which names the single block holding the door shut — the alarm rings for
    /// every sitting, including ones that don't gate and ones queued behind the
    /// first, so it needs the whole list rather than the front of it.
    func unwrittenBlocks(on date: Date = .now) -> [JournalBlock] {
        let entry = entry(on: date)
        return activeBlocks().filter { entry?.isComplete($0.id) != true }
    }

    /// The same list as ids, which is what `AlarmService` takes.
    func unwrittenBlockIDs(on date: Date = .now) -> Set<UUID> {
        Set(unwrittenBlocks(on: date).map(\.id))
    }

    // MARK: - Reading prompts

    func prompts(for block: JournalBlock, enabledOnly: Bool = true) -> [JournalPrompt] {
        prompts(forBlock: block.id, enabledOnly: enabledOnly)
    }

    func prompts(forBlock blockID: UUID, enabledOnly: Bool = true) -> [JournalPrompt] {
        let descriptor = FetchDescriptor<JournalPrompt>(
            sortBy: [SortDescriptor(\.order)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            $0.blockID == blockID && (!enabledOnly || $0.isEnabled)
        }
    }

    func allPrompts() -> [JournalPrompt] {
        let descriptor = FetchDescriptor<JournalPrompt>(sortBy: [SortDescriptor(\.order)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Roughly how long a block takes to answer honestly. Shown while the
    /// user builds their page, where the job is to keep setup enthusiasm from
    /// writing a cheque 6am has to cash.
    func estimatedSeconds(for block: JournalBlock) -> Int {
        prompts(for: block).reduce(0) { $0 + $1.style.estimatedSeconds }
    }

    // MARK: - The one invariant

    /// True when switching this prompt off, or deleting it, would leave the
    /// gating block with no questions at all. The single rule the library
    /// enforces — everything else about a prompt is the user's business.
    ///
    /// Only a *gating* block is protected. A block that doesn't lock the phone
    /// can be emptied to nothing; it simply stops appearing on Today, which is
    /// a perfectly reasonable thing to want and used to be impossible.
    func wouldStrandGate(_ prompt: JournalPrompt) -> Bool {
        guard prompt.isEnabled,
              let block = block(id: prompt.blockID),
              block.gatesDay
        else { return false }
        return prompts(for: block).count <= 1
    }

    // MARK: - Editing prompts

    /// Returns false when the change was refused, so the caller can say why
    /// rather than silently doing nothing.
    @discardableResult
    func setEnabled(_ isEnabled: Bool, on prompt: JournalPrompt) -> Bool {
        if !isEnabled, wouldStrandGate(prompt) { return false }
        prompt.isEnabled = isEnabled
        try? context.save()
        return true
    }

    @discardableResult
    func addPrompt(
        title: String,
        hint: String,
        style: PromptStyle,
        role: PromptRole = .open,
        originKey: String = "",
        to block: JournalBlock
    ) -> JournalPrompt {
        let next = (allPrompts().map(\.order).max() ?? -1) + 1
        let prompt = JournalPrompt(
            title: title, hint: hint, style: style,
            role: role,
            // Kept in step with the block so a backup read by an older build
            // still files this prompt somewhere sensible.
            session: block.gatesDay || block.hour < 14 ? .morning : .evening,
            blockID: block.id,
            order: next,
            originKey: originKey
        )
        context.insert(prompt)
        // The block can be answered now, so it locks and reminds — see
        // `JournalBlock.gatesDay`. This is the other half of the rule
        // `repairLibraryIfNeeded` enforces.
        block.gatesDay = true
        block.remindersEnabled = true
        renumber()
        return prompt
    }

    /// Adds one of the ready-made wordings to a block. The path most users
    /// take: choosing between six phrasings takes two seconds, and writing a
    /// good prompt from nothing is harder than journaling.
    @discardableResult
    func addPrompt(_ variant: PromptVariant, to block: JournalBlock) -> JournalPrompt {
        addPrompt(
            title: variant.title,
            hint: variant.hint,
            style: variant.style,
            role: PromptRole.owning(variant.key) ?? .open,
            originKey: variant.key,
            to: block
        )
    }

    /// Moves a prompt to another block, keeping it at the end of its new page.
    func move(_ prompt: JournalPrompt, to block: JournalBlock) -> Bool {
        guard prompt.blockID != block.id else { return true }
        // Emptying a gate by dragging its last question out is the same hazard
        // as deleting it.
        guard !wouldStrandGate(prompt) else { return false }
        prompt.blockID = block.id
        prompt.order = (allPrompts().map(\.order).max() ?? -1) + 1
        renumber()
        return true
    }

    @discardableResult
    func deletePrompt(_ prompt: JournalPrompt) -> Bool {
        guard !wouldStrandGate(prompt) else { return false }
        context.delete(prompt)
        renumber()
        return true
    }

    /// Swaps a prompt for another wording of the same question. This is the
    /// cheap move the whole feature leans on: choosing between six phrasings
    /// takes two seconds, and writing a good prompt from nothing does not.
    func apply(_ variant: PromptVariant, to prompt: JournalPrompt) {
        prompt.title = variant.title
        prompt.hint = variant.hint
        prompt.style = variant.style
        prompt.originKey = variant.key
        if let role = PromptRole.owning(variant.key) { prompt.role = role }
        try? context.save()
    }

    /// Reorders within one block. `order` stays global — blocks in time order,
    /// prompts in page order within each — so a single sort still produces the
    /// reading order for a whole day.
    func movePrompts(in block: JournalBlock, from source: IndexSet, to destination: Int) {
        var group = prompts(for: block, enabledOnly: false)
        group.move(fromOffsets: source, toOffset: destination)
        for (index, prompt) in group.enumerated() {
            // Fractional within the block's slice; `renumber` flattens it.
            prompt.order = index
        }
        renumber(pinning: block.id, to: group)
    }

    /// Collapses `order` back to 0..<n, blocks in time order. Called after any
    /// insertion, deletion or move so gaps never accumulate.
    private func renumber(pinning blockID: UUID? = nil, to pinned: [JournalPrompt] = []) {
        var ordered: [JournalPrompt] = []
        for block in blocks() {
            if block.id == blockID {
                ordered += pinned
            } else {
                ordered += prompts(for: block, enabledOnly: false)
            }
        }
        for (index, prompt) in ordered.enumerated() { prompt.order = index }
        try? context.save()
    }

    // MARK: - Installing a page

    /// Replaces the library with a template's page.
    ///
    /// Destructive by design — "start from a different template" means start
    /// over — so every call site owes the user a warning when they have
    /// prompts of their own. See `PromptTemplate.catalog`.
    func install(_ template: PromptTemplate) {
        replaceLibrary { JournalPrompt.rows(for: template, blocks: $0) }
    }

    /// The page and the two sittings a new account starts with.
    ///
    /// Everyone gets the same five questions — three in the morning, two at
    /// night — because a starting page chosen from a quiz was a guess dressed
    /// up as personalisation, and the user can rewrite every word of this one
    /// in Settings the moment they disagree with it. What onboarding actually
    /// collects is the two *times*, which is the part the app cannot guess.
    ///
    /// Rebuilds both blocks rather than retiming whatever is there. This runs
    /// once, at the end of the quiz, and the state it has to be correct against
    /// includes a device where somebody else already set up four sittings —
    /// see `RootView.startSignUp`.
    func installStartingPage(
        morningHour: Int,
        morningMinute: Int,
        eveningHour: Int,
        eveningMinute: Int
    ) {
        for prompt in allPrompts() { context.delete(prompt) }
        for block in blocks() { context.delete(block) }

        // Both hold the lock. The morning one is owed from midnight and the
        // evening one from its own hour — `pendingGateBlock` sorts that out.
        let morning = JournalBlock(
            title: "Morning",
            hour: morningHour,
            minute: morningMinute,
            order: 0,
            gatesDay: true,
            remindersEnabled: true,
            legacySession: .morning
        )
        let evening = JournalBlock(
            title: "Evening",
            hour: eveningHour,
            minute: eveningMinute,
            order: 1,
            gatesDay: true,
            remindersEnabled: true,
            legacySession: .evening
        )
        context.insert(morning)
        context.insert(evening)

        let rows = JournalPrompt.rows(
            for: .classicFive,
            blocks: [.morning: morning.id, .evening: evening.id]
        )
        for row in rows { context.insert(row) }

        renumber()
        syncWakeTime()
    }

    private func replaceLibrary(with rows: ([JournalPrompt.Session: UUID]) -> [JournalPrompt]) {
        let map = sessionBlocks()
        let built = rows(map)
        // Never leave the app promptless, whatever the caller passed.
        guard built.contains(where: { $0.blockID == map[.morning] }) else { return }
        for existing in allPrompts() { context.delete(existing) }
        for row in built { context.insert(row) }
        renumber()
    }

    /// Where a template's two halves land now that blocks exist.
    ///
    /// A template still ships a morning set and an evening set, because that's
    /// what a starting page is; the user rearranges it afterwards. The morning
    /// goes to whichever block holds the gate, and the evening to the block
    /// that came from the old evening session — or a new one at 9pm.
    private func sessionBlocks() -> [JournalPrompt.Session: UUID] {
        let all = blocks()
        let morning = all.first(where: \.gatesDay) ?? all.first
        let evening = all.first { $0.legacySessionRaw == JournalPrompt.Session.evening.rawValue }
            ?? all.last { $0.id != morning?.id && $0.hour >= 17 }

        var map: [JournalPrompt.Session: UUID] = [:]
        if let morning { map[.morning] = morning.id }
        if let evening {
            map[.evening] = evening.id
        } else {
            let block = JournalBlock(
                title: "Evening", hour: 21,
                order: (all.map(\.order).max() ?? -1) + 1,
                legacySession: .evening
            )
            context.insert(block)
            map[.evening] = block.id
        }
        return map
    }

    func save() { try? context.save() }

    // MARK: - Entries

    func day(for date: Date = .now) -> Date {
        calendar.startOfDay(for: date)
    }

    func entry(on date: Date = .now) -> JournalEntry? {
        let target = day(for: date)
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.day == target }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Fetches today's entry, creating it if this is the first prompt answered.
    func entryOrCreate(on date: Date = .now) -> JournalEntry {
        if let existing = entry(on: date) { return existing }
        let entry = JournalEntry(day: day(for: date))
        context.insert(entry)
        try? context.save()
        return entry
    }

    func allEntries() -> [JournalEntry] {
        let descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Removes a day for good. Answers go with it through the cascade rule on
    /// the relationship.
    ///
    /// Returns the day that was removed so the caller can have backup drop the
    /// server's copy too — without that, the next sync pulls the day straight
    /// back down and the delete looks like it never happened.
    @discardableResult
    func deleteEntry(_ entry: JournalEntry) -> Date {
        let day = day(for: entry.day)
        context.delete(entry)
        try? context.save()
        return day
    }

    // MARK: - Recording a session

    /// Writes a session's answers, replacing any previous answers for the same
    /// prompts so re-editing a day doesn't duplicate rows.
    ///
    /// `markComplete` is what actually lifts the gate. It's separated from the
    /// write so the user's words are safe on disk the moment they finish the
    /// last prompt, even if they kill the app on the completion card — while
    /// the gate itself only lifts once they've acknowledged it.
    func record(
        block: JournalBlock,
        answers: [(prompt: JournalPrompt, lines: [String])],
        markComplete: Bool = true,
        on date: Date = .now
    ) {
        let entry = entryOrCreate(on: date)

        let incomingIDs = Set(answers.map(\.prompt.id))
        for stale in entry.answers
        where stale.blockID == block.id && incomingIDs.contains(stale.promptID) {
            context.delete(stale)
        }

        for item in answers {
            let cleaned = item.lines.map { $0.trimmed }
            guard cleaned.contains(where: { !$0.isEmpty }) else { continue }
            // The time, not the hour's name: this is what History shows, and
            // it should say the same thing the rest of the app does. Answers
            // written before this keep the wording they were filed under.
            let answer = PromptAnswer(prompt: item.prompt, blockTitle: block.timeLabel, lines: cleaned)
            answer.entry = entry
            context.insert(answer)
        }

        if markComplete { stamp(entry, block: block) }
        touch(entry)

        try? context.save()
    }

    /// Marks a block finished. Separate from `record` so the completion card
    /// can be shown before the gate lifts.
    func markComplete(block: JournalBlock, on date: Date = .now) {
        let entry = entryOrCreate(on: date)
        stamp(entry, block: block)
        touch(entry)
        try? context.save()
    }

    /// Marks an entry as changed for sync purposes. Every mutation path has to
    /// go through here or backup will decide the server's older copy wins.
    private func touch(_ entry: JournalEntry) {
        entry.updatedAt = .now
    }

    private func stamp(_ entry: JournalEntry, block: JournalBlock) {
        let now = Date.now
        entry.markComplete(block.id, at: now)

        // The page is written, so the rest of this block's alarm chain has
        // nothing left to ask for. Cancelled here rather than in the view,
        // because every path that finishes a block comes through this one.
        AlarmService.shared.cancelChain(for: block.id)

        // The two legacy timestamps are still written, because a phone still on
        // the old build may pull this day back down from backup and has nothing
        // else to read. The gating block is that build's "morning" — which is
        // the flag its gate depends on.
        if block.gatesDay || block.legacySessionRaw == JournalPrompt.Session.morning.rawValue {
            entry.morningCompletedAt = now
        } else if block.legacySessionRaw == JournalPrompt.Session.evening.rawValue {
            entry.eveningCompletedAt = now
        }
    }

    // MARK: - Streaks

    /// Consecutive days ending today (or yesterday, if today isn't done yet)
    /// with at least one block written.
    ///
    /// Any block counts. Someone whose only sitting is at 9pm has kept the
    /// habit as surely as someone who writes at dawn, and tying the streak to
    /// one designated block would punish a day that was journaled properly at
    /// the wrong hour.
    /// Pass `assumingTodayComplete` on the completion card, where the writing
    /// is done but the gate hasn't been acknowledged yet — otherwise the
    /// celebration screen shows a number one lower than the truth.
    func currentStreak(asOf date: Date = .now, assumingTodayComplete: Bool = false) -> Int {
        var completedDays = Set(
            allEntries().filter(\.isAnyBlockComplete).map { calendar.startOfDay(for: $0.day) }
        )
        if assumingTodayComplete { completedDays.insert(calendar.startOfDay(for: date)) }
        guard !completedDays.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: date)
        // Today not done yet shouldn't break yesterday's streak.
        if !completedDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var totalCompletedDays: Int {
        allEntries().filter(\.isAnyBlockComplete).count
    }

    /// Erases every trace of the previous account's journal from this device.
    ///
    /// Only ever called when a *different* user signs in — see `LocalOwnership`.
    /// Prompts go too: a rewritten prompt library is as personal as an entry.
    func wipeLocalJournal() {
        try? context.delete(model: PromptAnswer.self)
        try? context.delete(model: JournalEntry.self)
        try? context.delete(model: JournalPrompt.self)
        try? context.delete(model: JournalBlock.self)
        try? context.save()
        // Leave the app usable rather than promptless.
        prepareLibrary()
    }

    // MARK: - Backup

    /// Days written here that the server doesn't have the current version of.
    ///
    /// This is what the warning banner counts. It is deliberately derived from
    /// the entries themselves rather than from a "last synced" timestamp: a
    /// sync that half-succeeded would leave a timestamp looking healthy while
    /// individual days were still missing.
    var pendingBackupCount: Int {
        allEntries().filter { entry in
            guard let backedUpAt = entry.backedUpAt else { return true }
            return backedUpAt < entry.updatedAt
        }.count
    }

    /// Records that the server now holds this version of a day.
    func markBackedUp(_ entry: JournalEntry, at version: Date) {
        entry.backedUpAt = version
    }


    /// Flattens a day into the plaintext struct that gets encrypted. Nothing
    /// here is uploaded as-is — see `BackupController`.
    func snapshot(_ entry: JournalEntry) -> EntryPayload {
        EntryPayload(
            createdAt: entry.createdAt,
            mood: entry.mood,
            morningCompletedAt: entry.morningCompletedAt,
            eveningCompletedAt: entry.eveningCompletedAt,
            completions: entry.completions,
            answers: entry.answers.sorted { $0.order < $1.order }.map {
                EntryPayload.Answer(
                    promptID: $0.promptID,
                    promptTitle: $0.promptTitle,
                    session: $0.sessionRaw,
                    order: $0.order,
                    lines: $0.lines,
                    blockID: $0.blockID,
                    blockTitle: $0.blockTitle
                )
            }
        )
    }

    /// The day's shape, for the settings backup.
    func blockSnapshots() -> [SettingsPayload.Block] {
        blocks().map {
            SettingsPayload.Block(
                id: $0.id,
                title: $0.title,
                hour: $0.hour,
                minute: $0.minute,
                order: $0.order,
                gatesDay: $0.gatesDay,
                remindersEnabled: $0.remindersEnabled,
                legacySession: $0.legacySessionRaw
            )
        }
    }

    /// The prompt library, for the settings backup.
    func promptSnapshots() -> [SettingsPayload.Prompt] {
        allPrompts()
            .map {
                SettingsPayload.Prompt(
                    id: $0.id,
                    title: $0.title,
                    hint: $0.hint,
                    lineCount: $0.lineCount,
                    session: $0.sessionRaw,
                    order: $0.order,
                    isEnabled: $0.isEnabled,
                    isBuiltIn: $0.isBuiltIn,
                    styleKind: $0.styleKindRaw,
                    role: $0.roleRaw,
                    originTemplateID: $0.originTemplateID,
                    originKey: $0.originKey,
                    blockID: $0.blockID
                )
            }
            // Sorted so the same library always hashes the same way, whatever
            // order SwiftData happened to hand it back in.
            .sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    /// Replaces the prompt library with a restored one.
    ///
    /// Ids are carried over from the snapshot rather than regenerated, so
    /// answers restored alongside still point at the question they were written
    /// against. Refuses an empty set: that would strand every prompt-driven
    /// screen with nothing to show, and no real backup is ever legitimately
    /// empty — `seedPromptsIfNeeded` guarantees at least the defaults.
    func applyPrompts(
        _ snapshots: [SettingsPayload.Prompt],
        blocks blockSnapshots: [SettingsPayload.Block] = []
    ) {
        guard !snapshots.isEmpty else { return }

        for existing in allPrompts() { context.delete(existing) }

        // A v3 backup carries the day's shape; a v1 or v2 one carries only
        // "morning" and "evening", and the two blocks already on this device
        // stand in for them. Either way the ids below have to resolve, or every
        // restored prompt lands in a block that isn't there.
        var fallback = sessionBlocks()
        if !blockSnapshots.isEmpty {
            for existing in blocks() { context.delete(existing) }
            for snapshot in blockSnapshots {
                let block = JournalBlock(
                    title: snapshot.title,
                    hour: snapshot.hour,
                    minute: snapshot.minute,
                    order: snapshot.order,
                    gatesDay: snapshot.gatesDay,
                    remindersEnabled: snapshot.remindersEnabled,
                    legacySession: JournalPrompt.Session(rawValue: snapshot.legacySession)
                )
                block.id = snapshot.id
                context.insert(block)
            }
            try? context.save()
            fallback = sessionBlocks()
        }

        for snapshot in snapshots {
            let prompt = JournalPrompt(
                title: snapshot.title,
                hint: snapshot.hint,
                style: PromptStyle.make(
                    kind: PromptStyle.Kind(rawValue: snapshot.styleKind) ?? .lines,
                    lineCount: snapshot.lineCount
                ),
                role: PromptRole(rawValue: snapshot.role) ?? .open,
                session: JournalPrompt.Session(rawValue: snapshot.session) ?? .morning,
                blockID: snapshot.blockID
                    ?? fallback[JournalPrompt.Session(rawValue: snapshot.session) ?? .morning],
                order: snapshot.order,
                isBuiltIn: snapshot.isBuiltIn,
                isEnabled: snapshot.isEnabled,
                originTemplateID: snapshot.originTemplateID,
                originKey: snapshot.originKey
            )
            prompt.id = snapshot.id
            context.insert(prompt)
        }
        try? context.save()

        // A v1 backup carries no roles, and a library restored from a device
        // running the old build can arrive with every morning prompt switched
        // off. Both are fixed here rather than at the next launch, so the
        // restored page is correct the moment it lands.
        migratePromptOriginsIfNeeded()
        repairLibraryIfNeeded()
        syncWakeTime()
    }

    /// What a v1 day's two timestamps mean in block terms. Without this a
    /// restore from an old phone would show every day as never written, and
    /// take the streak down with it.
    private static func completions(
        morning: Date?,
        evening: Date?,
        sessions: [JournalPrompt.Session: UUID]
    ) -> [BlockCompletion] {
        var found: [BlockCompletion] = []
        if let morning, let id = sessions[.morning] {
            found.append(BlockCompletion(blockID: id, at: morning))
        }
        if let evening, let id = sessions[.evening] {
            found.append(BlockCompletion(blockID: id, at: evening))
        }
        return found
    }

    /// Writes a decrypted day back into the local store, replacing whatever was
    /// there. Callers must have already decided this copy wins — the comparison
    /// lives in `BackupController`, not here.
    ///
    /// `updatedAt` is taken from the server rather than set to now, so a pull
    /// doesn't make every downloaded day look freshly edited and bounce
    /// straight back up on the next push.
    func apply(_ payload: EntryPayload, day: Date, updatedAt: Date) {
        let entry = entryOrCreate(on: day)

        for stale in entry.answers { context.delete(stale) }

        // A v1 payload knows only "morning" and "evening"; this device's own
        // blocks are what those two names mean here.
        let sessions = sessionBlocks()
        func blockID(for item: EntryPayload.Answer) -> UUID {
            item.blockID
                ?? sessions[JournalPrompt.Session(rawValue: item.session) ?? .morning]
                ?? sessions[.morning]
                ?? UUID()
        }

        for item in payload.answers {
            let answer = PromptAnswer(
                promptID: item.promptID,
                promptTitle: item.promptTitle,
                sessionRaw: item.session,
                blockID: blockID(for: item),
                blockTitle: item.blockTitle
                    ?? (JournalPrompt.Session(rawValue: item.session) ?? .morning).label,
                order: item.order,
                lines: item.lines
            )
            answer.entry = entry
            context.insert(answer)
        }

        entry.mood = payload.mood
        entry.createdAt = payload.createdAt
        entry.morningCompletedAt = payload.morningCompletedAt
        entry.eveningCompletedAt = payload.eveningCompletedAt
        entry.completions = payload.completions ?? Self.completions(
            morning: payload.morningCompletedAt,
            evening: payload.eveningCompletedAt,
            sessions: sessions
        )
        entry.updatedAt = updatedAt
        // It came from the server, so the server has it.
        entry.backedUpAt = updatedAt

        try? context.save()
    }
}
