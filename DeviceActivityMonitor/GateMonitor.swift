import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Raises the shield when the app isn't running.
///
/// Without this the whole feature is only as reliable as the user opening the
/// app: `ShieldService` applies the shield from `RootView`, so a phone that
/// sits untouched overnight wakes with yesterday's shield cleared and today's
/// never applied — the one morning it most needed to be there. The app
/// registers a window at midnight and one at each gating block's own time; the
/// system launches this extension at the start of each, and we shield every
/// category — the same rule `ShieldService.apply` follows, and for the same
/// reason.
///
/// What is owed is worked out here, from the schedule the app mirrors into the
/// app group. It used to be read off a single "currently owed" snapshot, which
/// quietly made the whole extension useless in the common case: the snapshot is
/// only as fresh as the last time the app ran, so a user who wrote yesterday's
/// page left behind a note saying "nothing owed", and this extension dutifully
/// took the shield *down* at midnight and never put it back. See
/// `GateBridge.pendingBlock(now:)`.
///
/// Clearing when the page is written is still the app's job — only the app
/// knows that has happened at the moment it happens.
final class GateMonitor: DeviceActivityMonitor {

    /// The default store, the same one `ShieldService` writes to. Unnamed on
    /// purpose — see `GateSelection.store`.
    private let store = GateSelection.store()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reconcile(activity: activity.rawValue, event: "start")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reconcile(activity: activity.rawValue, event: "end")
    }

    /// A minute of use inside the window. The only callback that arrives while
    /// the user is still *inside* the app they are about to lose, which makes
    /// it the one that lands the shield on them where they are rather than the
    /// next time they open something. See `GateScheduler.reachEvent`.
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        reconcile(activity: activity.rawValue, event: "reach")
    }

    // MARK: -

    /// Makes the shield match the one rule, whatever woke us.
    ///
    /// Every callback runs this and nothing else. No callback *means* anything
    /// — not "apply", not "clear" — they are all just opportunities to look at
    /// the clock and the mirrored schedule and decide from scratch.
    ///
    /// This replaced a version where the callbacks carried the meaning: start
    /// applied the shield, end cleared it. That makes the shield's state the
    /// sum of which callbacks iOS actually chose to deliver — and it does not
    /// guarantee delivery. The phone can be off at the block's hour, the
    /// extension can lose a jetsam coin-toss, the system can simply be busy.
    /// Under the old shape a single missed start was a whole day with no
    /// shield, and nothing anywhere could notice, because no process ever
    /// asked whether the shield *should* be up — they only reacted to moments.
    ///
    /// Because it decides rather than reacts, running it twice costs nothing
    /// and a missed callback costs only the wait until the next one. That is
    /// what makes the redundant windows in `GateScheduler` safe to register.
    private func reconcile(activity: String, event: String) {
        let enabled = GateBridge.isShieldingEnabled
        let pending = GateBridge.pendingBlock()
        let shouldShield = enabled && pending != nil

        // `AuthorizationCenter` reports `notDetermined` in this extension on a
        // device where the app reports `Approved`. That is the framework being
        // unreliable inside an extension sandbox, not the authorization being
        // absent — so it is evidence to record, never a reason to sit out the
        // job this process exists for.
        //
        // The asymmetry is the point. **Raising** a shield while possibly
        // unentitled costs nothing: worst case the write is ignored and the
        // situation is exactly as it was. **Lowering** one is the dangerous
        // direction, because a clear that iOS does honour would open the phone
        // for the rest of the day with no process left awake to notice. So the
        // clear waits for authorization it can actually see, and the apply
        // never does.
        //
        // A previous build gated *both* directions on that unreliable status,
        // which quietly switched off the only thing in this app that can reach
        // someone mid-scroll. `eventDidReachThreshold` is delivered here and
        // nowhere else — it is the one callback that arrives while the user is
        // still inside the app — and it landed in a branch that had decided not
        // to write. The shield then waited for them to leave Instagram, which
        // is exactly the symptom SleepBlock does not have.
        let authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if shouldShield {
            GateSelection.apply(to: store)
        } else if authorized {
            GateSelection.clear(from: store)
        }

        // Read the store back. `ManagedSettingsStore` accepts a write and
        // discards it without a word when it isn't entitled to keep it, so
        // "we called apply" and "a shield exists" are different claims and only
        // this one distinguishes them.
        GateBridge.recordMonitor(
            .init(
                at: Date(),
                activity: activity,
                event: authorized ? event : "\(event)-unauth",
                shielded: shouldShield,
                pending: pending?.timeLabel,
                enabled: enabled,
                offered: GateSelection.current.applicationTokens.count,
                stored: store.shield.applications?.count ?? -1,
                authorized: Self.authorizationLabel
            )
        )
    }

    /// What this process, not the app, thinks the authorization is. The two can
    /// disagree: extensions are launched into their own sandbox and the app's
    /// answer is not carried across.
    private static var authorizationLabel: String {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: "approved"
        case .denied: "denied"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

}
