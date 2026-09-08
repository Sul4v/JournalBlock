import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Re-arms the shield when the app isn't running.
///
/// Without this the whole feature is only as reliable as the user opening the
/// app: `ShieldService` applies the shield from `RootView`, so a phone that
/// sits untouched overnight wakes with yesterday's shield cleared and today's
/// never applied — the one morning it most needed to be there. The app
/// registers a daily window per gating block; the system launches this
/// extension at the start of each one and we shield every category — the same
/// rule `ShieldService.apply` follows, and for the same reason.
///
/// Clearing is still the app's job. The shield comes down when the page is
/// written, and only the app knows that has happened.
final class GateMonitor: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .init(GateBridge.storeName))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        applyShield()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // End of the day's window. Whatever happened, the user is not held to
        // yesterday's page — a shield that survives midnight is a phone the
        // user cannot unlock by any action available to them.
        clearShield()
    }

    // MARK: -

    private func applyShield() {
        guard GateBridge.isShieldingEnabled, GateBridge.pendingBlock != nil else {
            clearShield()
            return
        }

        store.shield.applications = nil
        store.shield.applicationCategories = .all()
        store.shield.webDomains = nil
        store.shield.webDomainCategories = .all()
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}
