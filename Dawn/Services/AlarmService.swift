import Foundation
import Observation
import SwiftUI
import AlarmKit
import AppIntents

/// A real alarm — AlarmKit rings through silent mode and Focus, which a local
/// notification cannot. Waking the user is the trigger for the whole ritual, so
/// it deserves the real API rather than a notification pretending to be one.
///
/// Each block gets two kinds of alarm, and the split is the whole design:
///
///   - a **standing** alarm at the block's own time, repeating every day. It is
///     never cancelled for being answered — tomorrow needs it too — only when
///     the block moves, is deleted, or alarm mode goes off.
///   - a **chain** of re-arms behind it, five minutes apart. This is what makes
///     the alarm outlast being dismissed, and writing the page is the only
///     thing that clears it.
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorizationState: AlarmManager.AuthorizationState = .notDetermined
    private(set) var lastError: String?
    /// The re-arms, block by block. A block owns its chain, so writing one page
    /// can clear exactly that chain and leave the rest of the day standing.
    private(set) var scheduledAlarms: [UUID: [PendingAlarm]] = [:]
    /// The repeating alarm at each block's own time.
    private(set) var dailyAlarms: [UUID: DailyAlarm] = [:]

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let manager = AlarmManager.shared

    private init() {
        authorizationState = manager.authorizationState
        scheduledAlarms = Self.loadChains(from: defaults)
        dailyAlarms = Self.loadDailies(from: defaults)
        discardLegacySchedule()
    }

    var isAuthorized: Bool { authorizationState == .authorized }

    /// One re-arm: what AlarmKit calls it, and when it goes off.
    ///
    /// The date is recorded and not just the id, because the whole question
    /// `refresh` has to answer is how much ringing is still ahead of the user.
    /// Ids alone can't tell a block with an hour of alarms left from one whose
    /// chain has already fired itself out.
    struct PendingAlarm: Codable, Hashable {
        let id: UUID
        let fireDate: Date
    }

    /// A block's standing alarm, with the time it was armed for — which is how
    /// `refresh` notices the block has since been moved.
    struct DailyAlarm: Codable, Hashable {
        let id: UUID
        let hour: Int
        let minute: Int
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let state = try await manager.requestAuthorization()
            authorizationState = state
            lastError = state == .denied ? "Alarm permission was declined." : nil
            return state == .authorized
        } catch {
            authorizationState = manager.authorizationState
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Scheduling

    /// How long the user gets before it rings again, and how many re-arms are
    /// kept standing behind a block that still owes a page.
    ///
    /// AlarmKit always draws its own Stop button and an app cannot suppress or
    /// condition it, so "rings until the page is written" is built out of a
    /// chain rather than one un-dismissable alarm: stopping one buys five
    /// minutes, not the day.
    ///
    /// The chain doesn't run out on its own. `refresh` tops it back up to
    /// `standingRearms` every time the app gets a look at the day, and Stop
    /// runs `OpenJournalIntent`, which opens the app — so silencing a ring is
    /// itself what schedules the next hour of them. The only thing that clears
    /// a chain is `cancelChain`, which `JournalStore.stamp` calls the moment
    /// the page is written. A phone left face-down and never picked up still
    /// has `standingRearms` of ringing queued, which is the most that can be
    /// promised without the app running at all.
    private static let rearmInterval: TimeInterval = 5 * 60
    private static let standingRearms = 12

    /// A ceiling on how many alarms Dawn holds at once. Someone writing at four
    /// times a day would otherwise ask the system for fifty-odd, and AlarmKit
    /// is not obliged to take them. Standing alarms come off the top — losing
    /// one costs a whole morning — and the soonest re-arms get what's left,
    /// which is the right way to spend it: the next ring of an overdue block
    /// matters more than the twelfth re-arm of one due tonight.
    private static let maxScheduledAlarms = 32

    /// Arms the alarms after a deliberate act by the user — finishing the
    /// permissions primer, editing a block, switching into alarm mode. Asks for
    /// permission if it doesn't have it, which is only appropriate on a path
    /// the user started.
    ///
    /// `blocks` must be the blocks that can actually ring — the ones with
    /// something to ask; see `JournalStore.activeBlocks`. `owed` is the subset
    /// today's page hasn't answered yet; see `JournalStore.unwrittenBlockIDs`.
    func reschedule(
        for blocks: [JournalBlock],
        enabled: Bool,
        owed: Set<UUID>,
        on day: Date = .now
    ) async {
        guard enabled else { cancelAll(); return }
        if !isAuthorized {
            guard await requestAuthorization() else { return }
        }
        await refresh(for: blocks, enabled: enabled, owed: owed, on: day)
    }

    /// Brings the alarms in line with the day as it currently stands, and tops
    /// up the chain of any block that still owes a page.
    ///
    /// Safe to call on every foreground: the alarms a given day and owed list
    /// should have are computed from scratch and then diffed against the ones
    /// actually scheduled, so a call that changes nothing schedules nothing.
    /// Unlike `reschedule` it never puts up the permission dialog — a phone
    /// coming to the foreground is not a moment the user asked for one.
    func refresh(
        for blocks: [JournalBlock],
        enabled: Bool,
        owed: Set<UUID>,
        on day: Date = .now,
        now: Date = .now
    ) async {
        guard enabled else {
            // Nothing to do in reminder mode, and this runs on every
            // foreground — so don't rewrite two empty records each time.
            if !scheduledAlarms.isEmpty || !dailyAlarms.isEmpty { cancelAll() }
            return
        }
        guard isAuthorized else { return }
        await syncDailyAlarms(for: blocks)
        await apply(
            Self.desiredRearms(
                for: blocks,
                owed: owed,
                on: day,
                now: now,
                budget: max(0, Self.maxScheduledAlarms - dailyAlarms.count)
            )
        )
    }

    // MARK: - The standing alarm

    /// Keeps one repeating alarm per block, at the block's own time.
    ///
    /// This is what makes alarm mode survive a day. A fixed-date alarm is spent
    /// once it fires, so a schedule built entirely out of them rang on the day
    /// it was set up and never again — the user was woken on the morning they
    /// turned the feature on, and left to sleep through every morning after it.
    private func syncDailyAlarms(for blocks: [JournalBlock]) async {
        // Last one wins rather than trapping: `uniqueKeysWithValues` would
        // crash the app over duplicate ids, which is a data glitch, not a
        // reason to take the journal down.
        let byID = blocks.reduce(into: [UUID: JournalBlock]()) { $0[$1.id] = $1 }

        // A block that was deleted, emptied of prompts, or moved to a new time:
        // whatever it has standing is now ringing at the wrong hour.
        for (blockID, daily) in dailyAlarms {
            guard let block = byID[blockID],
                  block.hour == daily.hour,
                  block.minute == daily.minute
            else {
                try? manager.cancel(id: daily.id)
                dailyAlarms[blockID] = nil
                persist()
                continue
            }
        }

        for block in blocks where dailyAlarms[block.id] == nil {
            guard let id = await scheduleDaily(hour: block.hour, minute: block.minute) else {
                continue
            }
            dailyAlarms[block.id] = DailyAlarm(id: id, hour: block.hour, minute: block.minute)
            persist()
        }
    }

    private func scheduleDaily(hour: Int, minute: Int) async -> UUID? {
        let id = UUID()
        do {
            _ = try await manager.schedule(
                id: id,
                configuration: .alarm(
                    schedule: .relative(
                        Alarm.Schedule.Relative(
                            time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
                            // Every day. A block is a commitment to a time, and
                            // the app has no concept of a day off; someone who
                            // wants one deletes the block or leaves alarm mode.
                            repeats: .weekly(Locale.Weekday.everyDay)
                        )
                    ),
                    attributes: attributes(title: "Time to write"),
                    stopIntent: OpenJournalIntent()
                )
            )
            lastError = nil
            return id
        } catch {
            lastError = "Couldn't schedule the alarm: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - The chain

    /// One re-arm Dawn wants on the system.
    private struct Rearm: Hashable {
        let blockID: UUID
        let fireDate: Date
    }

    /// Every re-arm the owed blocks want, soonest first and capped.
    ///
    /// Deterministic in `now`: a re-arm is always the block's own time plus a
    /// whole number of intervals, never "five minutes from whenever this ran".
    /// That is what lets `apply` diff instead of tearing the day down and
    /// rebuilding it — an anchor that moved with the clock would cancel and
    /// re-schedule every alarm on every foreground.
    private static func desiredRearms(
        for blocks: [JournalBlock],
        owed: Set<UUID>,
        on day: Date,
        now: Date,
        budget: Int
    ) -> [Rearm] {
        let calendar = Calendar.current
        var candidates: [Rearm] = []

        for block in blocks where owed.contains(block.id) {
            let base = block.date(on: day, calendar: calendar)
            // Where in the chain the user is. Step 0 is the block's own time,
            // which the standing alarm owns, so the chain always starts at 1.
            // A block that came and went hours ago picks up at the next
            // interval boundary instead, so an app opened at 9:13 for a 7am
            // block queues 9:15 rather than ringing in the user's face.
            let elapsed = now.timeIntervalSince(base)
            let firstStep = max(1, elapsed < 0 ? 1 : Int(floor(elapsed / rearmInterval)) + 1)

            for offset in 0..<standingRearms {
                let step = firstStep + offset
                candidates.append(
                    Rearm(
                        blockID: block.id,
                        fireDate: base.addingTimeInterval(Double(step) * rearmInterval)
                    )
                )
            }
        }

        return candidates
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(budget)
            .map { $0 }
    }

    /// Diffs the re-arms the day wants against the ones the system holds.
    private func apply(_ wanted: [Rearm]) async {
        let wantedByBlock = Dictionary(grouping: wanted, by: \.blockID)

        // Drop everything the day no longer wants: re-arms that have already
        // fired, and the chains of blocks that were written, deleted or moved.
        for (blockID, pending) in scheduledAlarms {
            let keep = Set((wantedByBlock[blockID] ?? []).map(\.fireDate))
            for alarm in pending where !keep.contains(alarm.fireDate) {
                // Cancelling an alarm that has already gone off is a no-op the
                // system tolerates; forgetting it here is the actual point.
                try? manager.cancel(id: alarm.id)
            }
            scheduledAlarms[blockID] = pending.filter { keep.contains($0.fireDate) }
        }
        scheduledAlarms = scheduledAlarms.filter { !$0.value.isEmpty }
        persist()

        // Then add whatever is missing from the front of each chain.
        for (blockID, rearms) in wantedByBlock {
            let existing = Set((scheduledAlarms[blockID] ?? []).map(\.fireDate))
            for rearm in rearms.sorted(by: { $0.fireDate < $1.fireDate })
            where !existing.contains(rearm.fireDate) {
                guard let id = await schedule(at: rearm.fireDate) else { continue }
                scheduledAlarms[blockID, default: []]
                    .append(PendingAlarm(id: id, fireDate: rearm.fireDate))
                // Written after every single alarm rather than once at the end.
                // This runs on the way to the background as well as on the way
                // in, and a suspension between scheduling an alarm and
                // recording it would leave a ring on the system that
                // `cancelChain` has no id for — one that goes on ringing after
                // the page is written, which is the one failure this feature
                // cannot have.
                persist()
            }
            scheduledAlarms[blockID]?.sort { $0.fireDate < $1.fireDate }
        }

        persist()
    }

    private func schedule(at date: Date) async -> UUID? {
        let id = UUID()
        do {
            _ = try await manager.schedule(
                id: id,
                configuration: .alarm(
                    schedule: .fixed(date),
                    attributes: attributes(title: "Still owed"),
                    stopIntent: OpenJournalIntent()
                )
            )
            lastError = nil
            return id
        } catch {
            lastError = "Couldn't schedule the alarm: \(error.localizedDescription)"
            return nil
        }
    }

    private func attributes(title: String) -> AlarmAttributes<DawnAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(
                text: "Open \(AppConfig.appName)",
                textColor: .white,
                systemImageName: "sun.horizon.fill"
            )
        )
        return AlarmAttributes<DawnAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: DawnAlarmMetadata(),
            tintColor: Theme.Palette.ember
        )
    }

    // MARK: - Cancelling

    /// Called the moment a block's page is written: the rest of its chain has
    /// nothing left to ask for. This is the only way out of the chain, which is
    /// the whole design — every other exit buys minutes, not the day.
    ///
    /// The block's standing alarm deliberately survives. It belongs to tomorrow
    /// morning, not to the page just written.
    func cancelChain(for blockID: UUID) {
        guard let pending = scheduledAlarms.removeValue(forKey: blockID) else { return }
        for alarm in pending { try? manager.cancel(id: alarm.id) }
        persist()
    }

    func cancelAll() {
        for pending in scheduledAlarms.values {
            for alarm in pending { try? manager.cancel(id: alarm.id) }
        }
        for daily in dailyAlarms.values { try? manager.cancel(id: daily.id) }
        scheduledAlarms = [:]
        dailyAlarms = [:]
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let chains = scheduledAlarms.reduce(into: [String: [PendingAlarm]]()) { out, pair in
            out[pair.key.uuidString] = pair.value
        }
        if let data = try? JSONEncoder().encode(chains) {
            defaults.set(data, forKey: Self.chainKey)
        }

        let dailies = dailyAlarms.reduce(into: [String: DailyAlarm]()) { out, pair in
            out[pair.key.uuidString] = pair.value
        }
        if let data = try? JSONEncoder().encode(dailies) {
            defaults.set(data, forKey: Self.dailyKey)
        }
    }

    private static func loadChains(from defaults: UserDefaults) -> [UUID: [PendingAlarm]] {
        guard let data = defaults.data(forKey: chainKey),
              let raw = try? JSONDecoder().decode([String: [PendingAlarm]].self, from: data)
        else { return [:] }
        return raw.reduce(into: [UUID: [PendingAlarm]]()) { out, pair in
            guard let key = UUID(uuidString: pair.key) else { return }
            out[key] = pair.value.sorted { $0.fireDate < $1.fireDate }
        }
    }

    private static func loadDailies(from defaults: UserDefaults) -> [UUID: DailyAlarm] {
        guard let data = defaults.data(forKey: dailyKey),
              let raw = try? JSONDecoder().decode([String: DailyAlarm].self, from: data)
        else { return [:] }
        return raw.reduce(into: [UUID: DailyAlarm]()) { out, pair in
            guard let key = UUID(uuidString: pair.key) else { return }
            out[key] = pair.value
        }
    }

    /// Clears alarms left by the build that stored bare ids with no fire dates.
    ///
    /// They can't be folded into the new record — there is no way to tell which
    /// of them are still ahead of the user — and left alone they would ring on
    /// a chain nothing can cancel. Dropping them costs at most one morning's
    /// alarms on the upgrade launch, which `refresh` puts back.
    private func discardLegacySchedule() {
        guard let raw = defaults.dictionary(forKey: Self.legacyAlarmIDKey) as? [String: [String]]
        else { return }
        for ids in raw.values {
            for id in ids.compactMap(UUID.init(uuidString:)) { try? manager.cancel(id: id) }
        }
        defaults.removeObject(forKey: Self.legacyAlarmIDKey)
    }

    private static let chainKey = "dawn.blockAlarmChains"
    private static let dailyKey = "dawn.blockDailyAlarms"
    private static let legacyAlarmIDKey = "dawn.blockAlarmIDs"
}

/// AlarmKit requires metadata alongside the presentation; Dawn has a single
/// alarm so there's nothing to distinguish yet.
struct DawnAlarmMetadata: AlarmMetadata {
    init() {}
}

private extension Locale.Weekday {
    /// AlarmKit expresses "every day" as a weekly recurrence over all seven.
    static var everyDay: [Locale.Weekday] {
        [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    }
}
