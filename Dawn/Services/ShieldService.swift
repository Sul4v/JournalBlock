import Foundation
import Observation
import FamilyControls
import ManagedSettings

/// Extends the gate past this app: while today's pages are unwritten, the apps
/// the user picked are shielded system-wide via Screen Time.
///
/// The picked apps, not every app. `.all()` was tried twice and shielded
/// nothing on device either time, so the shield is built from
/// `FamilyActivityPicker` tokens — see `GateSelection`, which carries the
/// evidence. The consequence lives in `SettingsView`: an empty picker is the
/// feature switched off, so the app has to keep asking for one.
///
/// Requires the `com.apple.developer.family-controls` entitlement. Without it
/// authorization simply fails and the app falls back to the in-app gate only —
/// nothing here is allowed to crash or block the journal.
@Observable
final class ShieldService {
    static let shared = ShieldService()

    /// The default store, matching SleepBlock and `GateMonitor`. It was a
    /// named store (`dawn.morningGate`) and a shield applied to it never
    /// appeared on the phone. See `GateSelection.store`.
    @ObservationIgnored private let store = GateSelection.store()
    /// The shared app group, not `.standard`: the monitor extension re-applies
    /// this shield while the app isn't running, and it can only read the
    /// selection if both processes are looking at the same suite.
    @ObservationIgnored private let defaults = GateBridge.defaults ?? .standard

    private(set) var authorizationStatus: AuthorizationStatus
    private(set) var isShieldActive = false
    /// Surfaced in Settings so a missing entitlement is visible, not silent.
    private(set) var lastError: String?

    private init() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            lastError = nil
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            lastError = "Screen Time access wasn't granted. \(AppConfig.appName) will still gate itself."
        }
    }

    func refreshAuthorization() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    // MARK: - Shield

    /// Single entry point, called by `RootView` whenever the gate state changes.
    ///
    /// The schedule is mirrored into the app group whether or not a shield is
    /// applied, because both extensions read it — to decide whether to shield
    /// at all, and to name the sitting — and either may be launched a moment
    /// after the app has gone away.
    ///
    /// Whether *this* process shields is then resolved from the mirror rather
    /// than passed in, so the app and the extensions can never disagree about
    /// what is owed: there is one rule, in one place.
    func sync(schedule: GateBridge.GateSchedule, blockingEnabled: Bool) {
        GateBridge.schedule = schedule
        GateBridge.isShieldingEnabled = blockingEnabled
        setShieldActive(blockingEnabled && GateBridge.pendingBlock() != nil)
    }

    func setShieldActive(_ active: Bool) {
        guard isAuthorized else {
            if isShieldActive { clear() }
            recordTrace(event: "app-unauthorized", shielded: false)
            return
        }
        active ? apply() : clear()
        recordTrace(event: active ? "app-apply" : "app-clear", shielded: active)
    }

    /// Records the store's state on arrival, before this process writes
    /// anything.
    ///
    /// Every other trace entry is taken immediately after a write, which can
    /// only ever confirm that the writer can see its own work. This one is
    /// taken cold, at the moment the app comes back, and so is the only entry
    /// that says whether a shield *survived* while the app was away. A run of
    /// `app-apply stored=1` followed by `observe stored=0` is the whole bug in
    /// two lines.
    func observe() {
        recordTrace(event: "observe", shielded: isShieldActive)
    }

    /// The app's own line in the monitor's log, with the store read back.
    ///
    /// The extensions were the only processes writing traces, which made the
    /// app's half of the same job invisible — and the app is the process that
    /// runs when the user is actually looking at the phone.
    private func recordTrace(event: String, shielded: Bool) {
        GateBridge.recordMonitor(
            .init(
                at: Date(),
                activity: "app",
                event: event,
                shielded: shielded,
                pending: GateBridge.pendingBlock()?.timeLabel,
                enabled: GateBridge.isShieldingEnabled,
                offered: GateSelection.current.applicationTokens.count,
                stored: store.shield.applications?.count ?? -1,
                authorized: String(describing: authorizationStatus)
            )
        )
    }

    /// Apple exempts its own critical apps (Phone, Messages, Settings) from
    /// shielding regardless, which is the floor this can't go below.
    private func apply() {
        GateSelection.apply(to: store)
        clearLegacyStore()
        isShieldActive = true
    }

    private func clear() {
        GateSelection.clear(from: store)
        clearLegacyStore()
        isShieldActive = false
    }

    /// Empties the named store this app used to write to. An install that
    /// upgraded mid-shield has one standing there that nothing else will ever
    /// take down, and settings from every store are unioned — so a stale one
    /// is a shield the user cannot clear by writing their page.
    private func clearLegacyStore() {
        GateSelection.clear(from: ManagedSettingsStore(named: .init(GateBridge.legacyStoreName)))
    }

    /// Belt and braces: if the user leaves reminder mode, drop any live shield.
    func disable() {
        clear()
        GateBridge.isShieldingEnabled = false
        GateBridge.schedule = nil
    }
}
