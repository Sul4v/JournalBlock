import Foundation
import DeviceActivity
import FamilyControls

/// Registers the daily windows that let `GateMonitor` raise the shield while
/// the app isn't running.
///
/// Two kinds of window, and the split is the point:
///
///   - **one at midnight**, so the first block of the day is already holding
///     the door for someone who wakes before it. This matches
///     `JournalStore.pendingGateBlock`: someone who sets 7am and wakes at five
///     must not find the front door open.
///   - **one at each gating block's own time**, which is what puts the shield
///     up *at* seven o'clock. Without it there was no event at the block's
///     hour at all — the midnight window had already started, and a phone in
///     someone's pocket at 6:59 stayed unshielded through breakfast until they
///     next opened the app of their own accord. The one moment the feature
///     exists for was the one moment nothing fired.
///
/// Every window ends at 23:59 so the shield can never outlive the day it
/// belongs to — a shield the user cannot clear by writing today's page is a
/// bricked phone, and that failure has to be impossible rather than unlikely.
enum GateScheduler {

    private static let center = DeviceActivityCenter()

    /// DeviceActivity refuses an interval shorter than this, so a block late
    /// enough that its window can't reach 23:59 doesn't get one. It still gates
    /// — the midnight window covers it tomorrow, and the in-app gate is
    /// unaffected — it just doesn't get its own on-the-minute event.
    private static let minimumWindow = 15

    /// The system caps how many activities one app may monitor. Blocks are
    /// taken in time order and the midnight window is never given up, so the
    /// overflow lands on the latest sittings of a day that already has more
    /// than any real schedule needs.
    private static let maxActivities = 19

    /// Rebuilds the whole schedule. Wholesale rather than incremental for the
    /// same reason `ReminderService.reschedule` is: the cost of getting a
    /// partial update wrong is a shield that arrives at a time the user has
    /// already changed.
    static func reschedule(for blocks: [JournalBlock], enabled: Bool) {
        guard enabled else { stop(); return }

        let gating = blocks
            .filter(\.gatesDay)
            .sorted { ($0.minutesOfDay, $0.order) < ($1.minutesOfDay, $1.order) }
        guard !gating.isEmpty else { stop(); return }

        let dayEnd = 23 * 60 + 59
        var wanted: [(name: DeviceActivityName, start: Int, end: Int)] = [
            // Midnight, so the first block of the day is already holding the
            // door for someone who wakes before it.
            (DeviceActivityName("gate.midnight"), 0, dayEnd)
        ]

        for block in gating {
            // Midnight already has this minute, and a second window starting on
            // it is a duplicate the system would reject anyway.
            if block.minutesOfDay > 0, dayEnd - block.minutesOfDay >= minimumWindow {
                wanted.append(
                    (DeviceActivityName("gate.\(block.id.uuidString)"), block.minutesOfDay, dayEnd)
                )
            }
            // Short windows, not another run to the end of the day: only their
            // *start* is meaningful — the end lands in `reconcile` like
            // everything else — and a poke that overlaps every other poke is
            // harder for the system to schedule than a small one that doesn't.
            for offset in backupOffsets {
                let at = block.minutesOfDay + offset
                guard at + pokeMinutes <= dayEnd else { continue }
                wanted.append(
                    (
                        DeviceActivityName("gate.backup\(offset).\(block.id.uuidString)"),
                        at,
                        at + pokeMinutes
                    )
                )
            }
        }

        wanted = Array(wanted.prefix(maxActivities))

        // Only what is genuinely stale — a deleted block, a block moved to a
        // new hour, blocking switched off.
        //
        // **Never a blanket `stopMonitoring()`.** That is what this used to do,
        // at the top of every call, and this runs on every foreground: the
        // whole schedule was demolished and rebuilt each time the user opened
        // the app. The device trace showed the cost plainly — every callback we
        // ever recorded was an end-storm followed by a start-storm from that
        // rebuild, and not once, in any test, did a window fire on its own at a
        // block's minute. Registering is cheap and idempotent; tearing the
        // schedule down is not.
        let keep = Set(wanted.map(\.name))
        let stale = center.activities.filter { !keep.contains($0) }
        if !stale.isEmpty { center.stopMonitoring(stale) }

        for window in wanted {
            start(named: window.name, from: window.start, to: window.end)
        }
    }

    /// How long a backup poke's window runs. Only its start matters, but
    /// DeviceActivity refuses intervals shorter than 15 minutes.
    private static let pokeMinutes = 20

    /// How far past a block's time the redundant windows sit, in minutes.
    ///
    /// iOS does not promise to deliver `intervalDidStart`. The phone can be off
    /// at the block's hour, the extension can lose a jetsam coin-toss, the
    /// system can simply be busy — and with one window per block that silently
    /// cost the whole day, because the block's own minute was the single moment
    /// at which anything ever turned the shield on.
    ///
    /// Safe only because `GateMonitor.reconcile` decides rather than reacts: an
    /// extra poke into an already-shielded day is a no-op. Offsets rather than
    /// repeats of the same minute, because the failure they cover is transient
    /// — half an hour later the phone is usually back on.
    private static let backupOffsets = [30, 90]

    /// The event that catches someone already inside an app.
    ///
    /// A window's start callback fires at the block's minute, but applying a
    /// shield does not interrupt an app that is *already* open — iOS checks at
    /// launch. So someone mid-scroll at seven o'clock keeps scrolling, and only
    /// meets the shield the next time they open something. Verified on device:
    /// the monitor applied the shield on the minute and the phone in hand
    /// showed nothing.
    ///
    /// A usage threshold is the one signal that arrives while the user is still
    /// inside the app, because iOS wakes the extension when the metered time is
    /// reached. A minute of use inside the window and the shield lands on them
    /// where they are.
    ///
    /// Metering only. The selection has no say in *what* gets shielded — that
    /// stays every category, for everyone, exactly as before — so choosing
    /// nothing here costs the mid-app catch and nothing else. That is what
    /// makes this picker safe where the old one wasn't: it cannot be used to
    /// carve a hole in the block.
    ///
    /// Shielded apps accrue no screen time, so this can only ever fire before
    /// the shield is up, which is precisely when it is wanted.
    static let reachEvent = DeviceActivityEvent.Name("gate.reach")

    private static func reachEvents() -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        guard let data = GateBridge.selectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return [:] }

        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        let domains = selection.webDomainTokens
        guard !apps.isEmpty || !categories.isEmpty || !domains.isEmpty else { return [:] }

        return [
            reachEvent: DeviceActivityEvent(
                applications: apps,
                categories: categories,
                webDomains: domains,
                threshold: DateComponents(minute: 1)
            )
        ]
    }

    /// One repeating window.
    private static func start(named name: DeviceActivityName, from: Int, to: Int) {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: (from / 60) % 24, minute: from % 60),
            intervalEnd: DateComponents(hour: (to / 60) % 24, minute: to % 60),
            repeats: true
        )

        do {
            try center.startMonitoring(name, during: schedule, events: reachEvents())
        } catch {
            // A failed window costs the pre-launch shield at that moment — the
            // in-app gate and the app-foreground sync both still hold. Never
            // worth interrupting the user over.
        }
    }

    /// Drops every window this app owns. Used when the user turns blocking off
    /// or the journal is wiped for a different account.
    static func stop() {
        center.stopMonitoring()
    }
}
