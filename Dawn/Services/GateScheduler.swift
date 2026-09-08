import Foundation
import DeviceActivity

/// Registers the daily windows that let `GateMonitor` re-arm the shield while
/// the app isn't running.
///
/// One monitored activity per gating block. The first block of the day starts
/// its window at midnight rather than at its own hour, matching
/// `JournalStore.pendingGateBlock`: someone who sets 7am and wakes at five must
/// not find the front door open. Later blocks start when they arrive.
///
/// Every window ends at 23:59 so the shield can never outlive the day it
/// belongs to — a shield the user cannot clear by writing today's page is a
/// bricked phone, and that failure has to be impossible rather than unlikely.
enum GateScheduler {

    private static let center = DeviceActivityCenter()

    /// Rebuilds the whole schedule. Wholesale rather than incremental for the
    /// same reason `ReminderService.reschedule` is: the cost of getting a
    /// partial update wrong is a shield that arrives at a time the user has
    /// already changed.
    static func reschedule(for blocks: [JournalBlock], enabled: Bool) {
        center.stopMonitoring()
        guard enabled else { return }

        let gating = blocks
            .filter(\.gatesDay)
            .sorted { ($0.minutesOfDay, $0.order) < ($1.minutesOfDay, $1.order) }
        guard !gating.isEmpty else { return }

        for (index, block) in gating.enumerated() {
            // Midnight for the first, the block's own time for the rest.
            let start = index == 0
                ? DateComponents(hour: 0, minute: 0)
                : DateComponents(hour: block.hour, minute: block.minute)

            let schedule = DeviceActivitySchedule(
                intervalStart: start,
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )

            do {
                try center.startMonitoring(
                    DeviceActivityName("gate.\(block.id.uuidString)"),
                    during: schedule
                )
            } catch {
                // A failed window costs the pre-launch shield for that block —
                // the in-app gate and the app-foreground sync both still hold.
                // Never worth interrupting the user over.
                continue
            }
        }
    }

    /// Drops every window this app owns. Used when the user turns blocking off
    /// or the journal is wiped for a different account.
    static func stop() {
        center.stopMonitoring()
    }
}
