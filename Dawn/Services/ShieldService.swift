import Foundation
import Observation
import FamilyControls
import ManagedSettings

/// Extends the gate past this app: while today's pages are unwritten, the
/// chosen apps are shielded system-wide via Screen Time.
///
/// Requires the `com.apple.developer.family-controls` entitlement. Without it
/// authorization simply fails and the app falls back to the in-app gate only —
/// nothing here is allowed to crash or block the journal.
@Observable
final class ShieldService {
    static let shared = ShieldService()

    @ObservationIgnored private let store = ManagedSettingsStore(named: .dawnGate)
    @ObservationIgnored private let defaults = UserDefaults.standard

    private(set) var authorizationStatus: AuthorizationStatus
    private(set) var isShieldActive = false
    /// Surfaced in Settings so a missing entitlement is visible, not silent.
    private(set) var lastError: String?

    /// The apps and categories the user chose to lock behind the journal.
    var selection: FamilyActivitySelection {
        didSet { persistSelection() }
    }

    private init() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        selection = Self.loadSelection(from: defaults) ?? FamilyActivitySelection()
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

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
    func setShieldActive(_ active: Bool) {
        guard isAuthorized, hasSelection else {
            if isShieldActive { clear() }
            return
        }
        active ? apply() : clear()
    }

    private func apply() {
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        isShieldActive = true
    }

    private func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isShieldActive = false
    }

    /// Belt and braces: if the user turns the feature off, drop any live shield.
    func disable() {
        clear()
        selection = FamilyActivitySelection()
    }

    // MARK: - Persistence

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Self.selectionKey)
    }

    private static let selectionKey = "dawn.shieldSelection"

    private static func loadSelection(from defaults: UserDefaults) -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: selectionKey) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}

private extension ManagedSettingsStore.Name {
    static let dawnGate = Self("dawn.morningGate")
}
