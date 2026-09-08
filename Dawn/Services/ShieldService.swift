import Foundation
import Observation
import FamilyControls
import ManagedSettings

/// Extends the gate past this app: while today's pages are unwritten, every
/// app is shielded system-wide via Screen Time.
///
/// There is no app picker any more. Choosing which apps to lock was a way of
/// negotiating with yourself before the morning arrived, and a shield with an
/// empty selection — the state most people left it in — shielded nothing at
/// all while reporting itself on. Reminder mode now shields every category,
/// which is the promise the mode makes.
///
/// Requires the `com.apple.developer.family-controls` entitlement. Without it
/// authorization simply fails and the app falls back to the in-app gate only —
/// nothing here is allowed to crash or block the journal.
@Observable
final class ShieldService {
    static let shared = ShieldService()

    @ObservationIgnored private let store = ManagedSettingsStore(named: .dawnGate)
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
    /// `pending` is mirrored into the app group whether or not a shield is
    /// applied, because the shield extension reads it to name the sitting and
    /// may be launched a moment after the app has gone away.
    func sync(pending: GateBridge.PendingBlock?, blockingEnabled: Bool) {
        GateBridge.pendingBlock = pending
        GateBridge.isShieldingEnabled = blockingEnabled
        setShieldActive(blockingEnabled && pending != nil)
    }

    func setShieldActive(_ active: Bool) {
        guard isAuthorized else {
            if isShieldActive { clear() }
            return
        }
        active ? apply() : clear()
    }

    /// Every category, rather than a set of tokens.
    ///
    /// `.all(except:)` would be the way to spare this app by name, but an
    /// `ApplicationToken` can only come from a `FamilyActivityPicker` — there
    /// is no API that mints one for your own bundle id — so the exception set
    /// would be empty anyway. Apple exempts its own critical apps (Phone,
    /// Messages, Settings) from shielding regardless, which is the floor this
    /// can't go below.
    private func apply() {
        store.shield.applications = nil
        store.shield.applicationCategories = .all()
        // Web domains too, or Safari is shielded while any in-app browser
        // isn't — which turns "every other app is shut" into a puzzle with a
        // known answer.
        store.shield.webDomains = nil
        store.shield.webDomainCategories = .all()
        isShieldActive = true
    }

    private func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        isShieldActive = false
    }

    /// Belt and braces: if the user leaves reminder mode, drop any live shield.
    func disable() {
        clear()
        GateBridge.isShieldingEnabled = false
        GateBridge.pendingBlock = nil
    }
}

private extension ManagedSettingsStore.Name {
    /// Shared with `GateMonitor`, which writes to the same store from its own
    /// process. Two names would mean two stores, and a shield the app believes
    /// it cleared would still be standing.
    static let dawnGate = Self(GateBridge.storeName)
}
