import Foundation
import SwiftData

/// All reads and writes of journal data go through here, so the rules about
/// "one entry per day" and streak counting live in exactly one place.
@MainActor
final class JournalStore {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - Library setup

    /// Everything the prompt library needs on launch, in the order it needs it.
    /// One call site so the three steps can never run out of order.
    func prepareLibrary() {
        seedPromptsIfNeeded()
        migratePromptOriginsIfNeeded()
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

    /// Puts a library with no morning questions back into a usable state.
    ///
    /// An empty morning page is not a preference someone can hold: `JournalSession`
    /// reads it as "already finished", so the gate lifts with nothing written and
    /// the entire premise of the app is off. The guards below stop it happening
    /// now; this heals installs — and restored backups — from the build where
    /// every morning prompt could be switched off in Settings.
    func repairLibraryIfNeeded() {
        let morning = prompts(for: .morning, enabledOnly: false)
        guard !morning.contains(where: \.isEnabled) else { return }

        if let first = morning.first {
            first.isEnabled = true
        } else {
            let rows = JournalPrompt.rows(for: .classicFive).filter { $0.session == .morning }
            for row in rows { context.insert(row) }
            renumber()
        }
        try? context.save()
    }

    // MARK: - Reading prompts

    func prompts(for session: JournalPrompt.Session, enabledOnly: Bool = true) -> [JournalPrompt] {
        let descriptor = FetchDescriptor<JournalPrompt>(
            sortBy: [SortDescriptor(\.order)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter {
            $0.session == session && (!enabledOnly || $0.isEnabled)
        }
    }

    func allPrompts() -> [JournalPrompt] {
        let descriptor = FetchDescriptor<JournalPrompt>(sortBy: [SortDescriptor(\.order)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Roughly how long a session takes to answer honestly. Shown while the
    /// user builds their page, where the job is to keep setup enthusiasm from
    /// writing a cheque 6am has to cash.
    func estimatedSeconds(for session: JournalPrompt.Session) -> Int {
        prompts(for: session).reduce(0) { $0 + $1.style.estimatedSeconds }
    }

    // MARK: - The one invariant

    /// True when switching this prompt off, or deleting it, would leave the
    /// morning with no questions at all. The single rule the library enforces —
    /// everything else about a prompt is the user's business.
    func wouldStrandMorning(_ prompt: JournalPrompt) -> Bool {
        guard prompt.session == .morning, prompt.isEnabled else { return false }
        return prompts(for: .morning).count <= 1
    }

    // MARK: - Editing prompts

    /// Returns false when the change was refused, so the caller can say why
    /// rather than silently doing nothing.
    @discardableResult
    func setEnabled(_ isEnabled: Bool, on prompt: JournalPrompt) -> Bool {
        if !isEnabled, wouldStrandMorning(prompt) { return false }
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
        session: JournalPrompt.Session
    ) -> JournalPrompt {
        let next = (allPrompts().map(\.order).max() ?? -1) + 1
        let prompt = JournalPrompt(
            title: title, hint: hint, style: style,
            role: role, session: session, order: next
        )
        context.insert(prompt)
        renumber()
        return prompt
    }

    @discardableResult
    func deletePrompt(_ prompt: JournalPrompt) -> Bool {
        guard !wouldStrandMorning(prompt) else { return false }
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

    /// Reorders within one session. `order` stays global — morning rows first,
    /// then evening — so a single sort still produces the reading order.
    func movePrompts(
        in session: JournalPrompt.Session,
        from source: IndexSet,
        to destination: Int
    ) {
        var group = prompts(for: session, enabledOnly: false)
        group.move(fromOffsets: source, toOffset: destination)

        let others = allPrompts().filter { $0.session != session }
        let ordered = session == .morning ? group + others : others + group
        for (index, prompt) in ordered.enumerated() { prompt.order = index }
        try? context.save()
    }

    /// Collapses `order` back to 0..<n, morning first. Called after any
    /// insertion or deletion so gaps never accumulate.
    private func renumber() {
        let morning = prompts(for: .morning, enabledOnly: false)
        let evening = prompts(for: .evening, enabledOnly: false)
        for (index, prompt) in (morning + evening).enumerated() { prompt.order = index }
        try? context.save()
    }

    // MARK: - Installing a page

    /// Replaces the library with a template's page.
    ///
    /// Destructive by design — "start from a different template" means start
    /// over — so every call site owes the user a warning when they have
    /// prompts of their own. See `PromptTemplate.catalog`.
    func install(_ template: PromptTemplate) {
        replaceLibrary(with: JournalPrompt.rows(for: template))
    }

    /// Replaces the library with the page the quiz recommends.
    func install(_ plan: PromptPlan) {
        replaceLibrary(with: JournalPrompt.rows(for: plan))
    }

    private func replaceLibrary(with rows: [JournalPrompt]) {
        // Never leave the app promptless, whatever the caller passed.
        guard rows.contains(where: { $0.session == .morning }) else { return }
        for existing in allPrompts() { context.delete(existing) }
        for row in rows { context.insert(row) }
        try? context.save()
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

    // MARK: - Recording a session

    /// Writes a session's answers, replacing any previous answers for the same
    /// prompts so re-editing a day doesn't duplicate rows.
    ///
    /// `markComplete` is what actually lifts the gate. It's separated from the
    /// write so the user's words are safe on disk the moment they finish the
    /// last prompt, even if they kill the app on the completion card — while
    /// the gate itself only lifts once they've acknowledged it.
    func record(
        session: JournalPrompt.Session,
        answers: [(prompt: JournalPrompt, lines: [String])],
        mood: Int?,
        markComplete: Bool = true,
        on date: Date = .now
    ) {
        let entry = entryOrCreate(on: date)

        let incomingIDs = Set(answers.map(\.prompt.id))
        for stale in entry.answers where stale.session == session && incomingIDs.contains(stale.promptID) {
            context.delete(stale)
        }

        for item in answers {
            let cleaned = item.lines.map { $0.trimmed }
            guard cleaned.contains(where: { !$0.isEmpty }) else { continue }
            let answer = PromptAnswer(prompt: item.prompt, lines: cleaned)
            answer.entry = entry
            context.insert(answer)
        }

        if let mood { entry.mood = mood }
        if markComplete { stamp(entry, session: session) }
        touch(entry)

        try? context.save()
    }

    /// Marks a session finished. Separate from `record` so the completion card
    /// can be shown before the gate lifts.
    func markComplete(session: JournalPrompt.Session, on date: Date = .now) {
        let entry = entryOrCreate(on: date)
        stamp(entry, session: session)
        touch(entry)
        try? context.save()
    }

    /// Marks an entry as changed for sync purposes. Every mutation path has to
    /// go through here or backup will decide the server's older copy wins.
    private func touch(_ entry: JournalEntry) {
        entry.updatedAt = .now
    }

    private func stamp(_ entry: JournalEntry, session: JournalPrompt.Session) {
        switch session {
        case .morning: entry.morningCompletedAt = .now
        case .evening: entry.eveningCompletedAt = .now
        }
    }

    // MARK: - Streaks

    /// Consecutive days ending today (or yesterday, if today isn't done yet)
    /// with a completed morning session.
    /// Pass `assumingTodayComplete` on the completion card, where the writing
    /// is done but the gate hasn't been acknowledged yet — otherwise the
    /// celebration screen shows a number one lower than the truth.
    func currentStreak(asOf date: Date = .now, assumingTodayComplete: Bool = false) -> Int {
        var completedDays = Set(
            allEntries().filter(\.isMorningComplete).map { calendar.startOfDay(for: $0.day) }
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

    var totalCompletedMornings: Int {
        allEntries().filter(\.isMorningComplete).count
    }

    /// Erases every trace of the previous account's journal from this device.
    ///
    /// Only ever called when a *different* user signs in — see `LocalOwnership`.
    /// Prompts go too: a rewritten prompt library is as personal as an entry.
    func wipeLocalJournal() {
        try? context.delete(model: PromptAnswer.self)
        try? context.delete(model: JournalEntry.self)
        try? context.delete(model: JournalPrompt.self)
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
            answers: entry.answers.sorted { $0.order < $1.order }.map {
                EntryPayload.Answer(
                    promptID: $0.promptID,
                    promptTitle: $0.promptTitle,
                    session: $0.sessionRaw,
                    order: $0.order,
                    lines: $0.lines
                )
            }
        )
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
                    originKey: $0.originKey
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
    func applyPrompts(_ snapshots: [SettingsPayload.Prompt]) {
        guard !snapshots.isEmpty else { return }

        for existing in allPrompts() { context.delete(existing) }

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

        for item in payload.answers {
            let answer = PromptAnswer(
                promptID: item.promptID,
                promptTitle: item.promptTitle,
                sessionRaw: item.session,
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
        entry.updatedAt = updatedAt
        // It came from the server, so the server has it.
        entry.backedUpAt = updatedAt

        try? context.save()
    }
}
