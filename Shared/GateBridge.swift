import Foundation

/// The one channel between the app and its Screen Time extensions.
///
/// Shield extensions run in their own processes, launched by the system at
/// moments when the app itself may not be running at all. They cannot open the
/// SwiftData store, so everything a shield needs in order to name the block it
/// is standing in front of is mirrored into a shared app group the moment the
/// gate changes. If the mirror is empty the shields still work — they just fall
/// back to generic copy rather than saying "Morning, 7:00 AM".
///
/// Compiled into the app *and* all three extensions. Keep it free of SwiftUI,
/// SwiftData and anything else an extension can't afford to load.
enum GateBridge {

    /// Must match the `com.apple.security.application-groups` entitlement on
    /// every target. There is no way to discover this at runtime, so it is
    /// written once here and read everywhere.
    static let appGroup = "group.com.sulav.journalblock"

    static let urlScheme = "journalblock"

    /// **Retired.** The gate's shields lived in a `ManagedSettingsStore` named
    /// this, on the reasoning that a named store keeps one app's settings from
    /// trampling another's. Nothing applied to it ever appeared on the phone.
    /// Both processes now use the default unnamed store, matching SleepBlock —
    /// see `GateSelection.store`. Kept only so an install carrying a shield in
    /// the old store has something to clear it with.
    static let legacyStoreName = "dawn.morningGate"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // MARK: - What the shield is standing in front of

    /// The block the user owes, flattened to the few facts a shield can show.
    struct PendingBlock: Codable, Equatable, Sendable {
        var id: UUID
        /// The user's own name for the sitting — "Morning", "Wind down".
        var title: String
        /// Already localised, e.g. "7:00 AM". Formatting it here means the
        /// extension never has to build a `DateFormatter` on a cold launch.
        var timeLabel: String
        /// How many prompts the block asks, for "three questions" copy.
        var promptCount: Int
        /// Minutes since midnight for the block's time. `timeLabel` is already
        /// formatted and so is useless for arithmetic, but the shield needs to
        /// know *how late* the page is in order to pick its tone — and it has
        /// to know it without building a `DateFormatter` on a cold launch.
        var minutesOfDay: Int
        /// The SF Symbol `JournalBlock.icon` picked for this hour, so an
        /// evening shield doesn't show a sunrise.
        var symbolName: String

        init(
            id: UUID,
            title: String,
            timeLabel: String,
            promptCount: Int,
            minutesOfDay: Int,
            symbolName: String
        ) {
            self.id = id
            self.title = title
            self.timeLabel = timeLabel
            self.promptCount = promptCount
            self.minutesOfDay = minutesOfDay
            self.symbolName = symbolName
        }

        /// Hand-written so that `minutesOfDay`, added after this struct started
        /// shipping, doesn't throw on a mirror an older build left in the app
        /// group. The synthesised decoder treats a missing key as an error even
        /// when the property has a default, and the failure mode here is the
        /// shield falling back to generic copy for no reason. Zero reads as
        /// midnight, which makes every band "late" — wrong, but wrong in the
        /// direction that still shows the user something true.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            timeLabel = try container.decode(String.self, forKey: .timeLabel)
            promptCount = try container.decode(Int.self, forKey: .promptCount)
            minutesOfDay = try container.decodeIfPresent(Int.self, forKey: .minutesOfDay) ?? 0
            symbolName = try container.decode(String.self, forKey: .symbolName)
        }
    }

    /// Every gating block, and which of them today's page has already answered.
    ///
    /// This is deliberately the *schedule* rather than a snapshot of the one
    /// block currently owed. A snapshot can only ever be as fresh as the last
    /// time the app ran, and the moment that matters most — the block's own
    /// time, on a phone that has been in someone's pocket since last night —
    /// is precisely a moment the app has not seen. A snapshot taken after
    /// yesterday's page was written says "nothing owed", and the monitor
    /// extension, reading it at seven this morning, would take the shield down
    /// on the one morning it was built to put it up.
    ///
    /// With the schedule and a day-stamp, the extension can work out what is
    /// owed at any moment without the app's help. See `pendingBlock(now:)`.
    struct GateSchedule: Codable, Equatable, Sendable {
        /// Blocks that hold the door and have something to ask, in time order.
        /// Empty means the gate is off — a user before their first session day,
        /// or one with no gating blocks left.
        var blocks: [PendingBlock]
        /// The day `written` describes. A stamp from an earlier day means
        /// today's page is untouched, which is what makes the overnight case
        /// resolve correctly with no app process involved.
        var writtenDay: Date
        /// Blocks completed on `writtenDay`.
        var written: [UUID]

        init(blocks: [PendingBlock] = [], writtenDay: Date = .now, written: [UUID] = []) {
            self.blocks = blocks
            self.writtenDay = writtenDay
            self.written = written
        }
    }

    /// Written by the app whenever the gate changes. `nil` means the app has
    /// never synced, in which case the shields fall back to generic copy.
    static var schedule: GateSchedule? {
        get {
            guard let data = defaults?.data(forKey: Key.schedule) else { return nil }
            return try? JSONDecoder().decode(GateSchedule.self, from: data)
        }
        set {
            guard let defaults else { return }
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Key.schedule)
                return
            }
            defaults.set(data, forKey: Key.schedule)
        }
    }

    /// The block the user owes right now. `nil` means the phone is theirs —
    /// any shield still on screen is stale and should let them through.
    ///
    /// Must stay in step with `JournalStore.pendingGateBlock`, which is the
    /// same rule against SwiftData: the earliest unwritten gating block that
    /// has come due, with the first block of the day due from midnight so that
    /// waking early doesn't find the front door open.
    ///
    /// Cheap enough for `ShieldConfigurationProvider`, which has a few hundred
    /// milliseconds to return a whole screen: one small JSON decode, one
    /// same-day comparison, and integer arithmetic on minutes.
    static func pendingBlock(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PendingBlock? {
        guard let schedule, !schedule.blocks.isEmpty else { return nil }

        // A stamp from any other day tells us nothing about today's page, so
        // nothing counts as written. This is the whole overnight fix.
        let written: Set<UUID> = calendar.isDate(schedule.writtenDay, inSameDayAs: now)
            ? Set(schedule.written)
            : []

        let minutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)

        for (index, block) in schedule.blocks.enumerated() {
            guard !written.contains(block.id) else { continue }
            if index == 0 || minutes >= block.minutesOfDay { return block }
        }
        return nil
    }

    // MARK: - When it is

    /// Minutes since midnight, read once per screen so that everything keyed
    /// off the clock — the daypart vocabulary, how late the page is — can never
    /// disagree about what time it is.
    enum Clock {
        static func current(calendar: Calendar = .current, date: Date = Date()) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    /// What the hour is called. Picks the vocabulary — whether a line can say
    /// "morning" — separately from how hard that line leans.
    ///
    /// Shared rather than per-extension because the shield and the handoff
    /// notification are two halves of one moment: the user reads the shield,
    /// taps it, and lands on the banner seconds later. Two copies of these
    /// boundaries would eventually drift and let the pair contradict itself.
    enum Daypart {
        case dawn, morning, midday, afternoon, evening, night

        init(minutesOfDay: Int) {
            switch minutesOfDay / 60 {
            case 5..<8: self = .dawn
            case 8..<11: self = .morning
            case 11..<14: self = .midday
            case 14..<18: self = .afternoon
            case 18..<21: self = .evening
            default: self = .night
            }
        }
    }

    // MARK: - Did the monitor run?

    /// A breadcrumb per `GateMonitor` event.
    ///
    /// The monitor is launched by the system into its own process, with no UI,
    /// no console anyone can watch, and no way to report what it decided. When
    /// a morning goes by without a shield there is otherwise no way to tell
    /// "the extension never ran" from "it ran and resolved nothing owed" — two
    /// very different bugs that look identical from the outside. Both were
    /// guessed at, at length, before this existed.
    ///
    /// Bounded and tiny. It is read off the device with `devicectl` when a
    /// morning goes wrong.
    struct MonitorTrace: Codable, Equatable, Sendable {
        var at: Date
        var activity: String
        /// "start" or "end".
        var event: String
        /// What the monitor did to the shield.
        var shielded: Bool
        /// The block it resolved, or nil if it decided nothing was owed.
        var pending: String?
        /// What the mirror said about the mode, so a false here explains a
        /// cleared shield on its own.
        var enabled: Bool

        /// How many application tokens we handed `ManagedSettings`.
        var offered: Int?

        /// How many the store reports **back** immediately afterwards.
        ///
        /// The one fact nothing in this chain has ever checked. Every other
        /// signal here is this process describing its own intentions: the
        /// monitor ran, it resolved a block, it called apply. None of that says
        /// the write survived. `ManagedSettingsStore` fails silently when it
        /// declines a write — no throw, no error, no log — so a store that
        /// reads back nil right after being handed a token is the difference
        /// between "we never tried" and "we tried and iOS refused".
        var stored: Int?

        /// Family Controls authorization as seen from *this* process. The
        /// monitor never checked it, and an unauthorized write is exactly the
        /// kind iOS discards without saying so.
        var authorized: String?

        init(
            at: Date,
            activity: String,
            event: String,
            shielded: Bool,
            pending: String?,
            enabled: Bool,
            offered: Int? = nil,
            stored: Int? = nil,
            authorized: String? = nil
        ) {
            self.at = at
            self.activity = activity
            self.event = event
            self.shielded = shielded
            self.pending = pending
            self.enabled = enabled
            self.offered = offered
            self.stored = stored
            self.authorized = authorized
        }

        /// Tolerant of traces written before the three fields above existed —
        /// otherwise one old entry makes the whole log undecodable and the
        /// evidence disappears exactly when it is wanted.
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            at = try box.decode(Date.self, forKey: .at)
            activity = try box.decode(String.self, forKey: .activity)
            event = try box.decode(String.self, forKey: .event)
            shielded = try box.decode(Bool.self, forKey: .shielded)
            pending = try box.decodeIfPresent(String.self, forKey: .pending)
            enabled = try box.decode(Bool.self, forKey: .enabled)
            offered = try box.decodeIfPresent(Int.self, forKey: .offered)
            stored = try box.decodeIfPresent(Int.self, forKey: .stored)
            authorized = try box.decodeIfPresent(String.self, forKey: .authorized)
        }
    }

    private static let maxTrace = 20

    static var monitorTrace: [MonitorTrace] {
        get {
            guard let data = defaults?.data(forKey: Key.monitorTrace) else { return [] }
            return (try? JSONDecoder().decode([MonitorTrace].self, from: data)) ?? []
        }
        set {
            guard let defaults, let data = try? JSONEncoder().encode(newValue.suffix(maxTrace).map { $0 })
            else { return }
            defaults.set(data, forKey: Key.monitorTrace)
        }
    }

    static func recordMonitor(_ trace: MonitorTrace) {
        monitorTrace = monitorTrace + [trace]
    }

    /// The app's chosen apps and categories, as encoded `FamilyActivitySelection`.
    ///
    /// Stored as opaque data rather than a typed property so this file does not
    /// have to import FamilyControls — the shield extensions need the *bytes*
    /// only to hand back to `ManagedSettings`, and one of them (the action
    /// handler) doesn't need them at all.
    static var selectionData: Data? {
        get { defaults?.data(forKey: Key.selection) }
        set {
            guard let defaults else { return }
            if let newValue { defaults.set(newValue, forKey: Key.selection) }
            else { defaults.removeObject(forKey: Key.selection) }
        }
    }

    /// Mirrors `Preferences.blockAppsUntilDone`, so the monitor extension can
    /// tell "the user turned this off" from "there is nothing owed today".
    static var isShieldingEnabled: Bool {
        get { defaults?.bool(forKey: Key.shieldingEnabled) ?? false }
        set { defaults?.set(newValue, forKey: Key.shieldingEnabled) }
    }

    // MARK: - Getting back into the app

    /// `journalblock://block/<uuid>` — opens the app straight into that block's
    /// session. Handled in `DawnApp.onOpenURL`.
    static func deepLink(for blockID: UUID) -> URL {
        URL(string: "\(urlScheme)://block/\(blockID.uuidString)")!
    }

    /// Parses the link above back into a block id, or nil for any other URL.
    /// Kept here so the app and the extension can never drift apart on format.
    static func blockID(fromDeepLink url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host == "block" else { return nil }
        let raw = url.pathComponents.first { $0 != "/" }
        return raw.flatMap(UUID.init(uuidString:))
    }

    /// The identifier of the notification a shield posts to hand the user back
    /// to the app. One constant so the app can clear a stale one on launch.
    static let handoffNotificationID = "journalblock.shield.handoff"

    private enum Key {
        /// Not the old "gate.pendingBlock": that key held a single block with
        /// no day stamp, and a build reading it as a schedule would decode
        /// nothing. A fresh key means the first sync writes the truth.
        static let schedule = "gate.schedule"
        static let selection = "gate.shieldSelection"
        static let shieldingEnabled = "gate.shieldingEnabled"
        static let monitorTrace = "gate.monitorTrace"
    }
}
