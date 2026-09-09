import Foundation
import FamilyControls
import ManagedSettings

/// The apps the gate shuts, and the shield that shuts them.
///
/// ## Tokens, from the default store
///
/// This is deliberately the same shape SleepBlock ships, because that is the
/// version known to work on a real phone:
///
///   - the **default** `ManagedSettingsStore()`, not a named one
///   - explicit `ApplicationToken`s and `.specific(categoryTokens)`, never
///     `.all()`
///
/// Both halves were tried the other way here and neither shielded anything.
/// `.all()` was tested on device, found to shield nothing, and then reinstated
/// on the theory that a concurrent bug (`ShieldService` sampling the Family
/// Controls authorization once in `init` and never refreshing) had invalidated
/// that test. The theory was reasonable and the phone disagreed: with the
/// authorization bug fixed, `.all()` on a named store still let Instagram
/// straight through. The device is the authority here, not the reasoning.
///
/// ## Application tokens are the part that bites
///
/// A category policy on its own does not shield. Two separate attempts here
/// proved it on device: `.all()` across every category, and then
/// `.specific(categoryTokens)` built from thirteen categories the user picked.
/// Both left `shield.applications` empty, and both let Instagram open. The
/// shield only holds when `applicationTokens` is non-empty, which is why the
/// pickers are built with `includeEntireCategory: true` — that is what turns a
/// category tap into the concrete apps inside it.
///
/// `isEmpty` below is therefore the wrong question to ask about whether the
/// gate works. `shieldsNothing` is the right one.
///
/// The cost is real and has to be stated plainly: **an empty selection shields
/// nothing.** There is no API that mints an `ApplicationToken` outside a
/// `FamilyActivityPicker`, so the gate is only ever as wide as the user makes
/// it. That is why the picker is presented in the permissions primer and again
/// from Settings whenever the selection is empty — an unset picker is the
/// feature being off, and it must never be able to sit there quietly.
///
/// Apple exempts its own critical apps — Phone, Messages, Settings — from
/// shielding regardless, which is the floor this cannot go below.
enum GateSelection {

    /// The store every process writes to.
    ///
    /// Unnamed, matching SleepBlock. A named store is the documented way to
    /// keep one app's settings separate from another's, and this app used
    /// `dawn.morningGate` for exactly that reason — but a shield applied to it
    /// never appeared, and the default store is the configuration with device
    /// evidence behind it.
    static func store() -> ManagedSettingsStore { ManagedSettingsStore() }

    static var current: FamilyActivitySelection {
        guard let data = GateBridge.selectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static var isEmpty: Bool {
        let selection = current
        return selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    /// True when applying this selection would leave the phone open.
    ///
    /// Distinct from `isEmpty`, and the distinction is the whole bug: a
    /// selection holding thirteen categories and no apps is not empty, reports
    /// itself as thirteen things chosen, and shields nothing whatsoever.
    static var shieldsNothing: Bool {
        let selection = current
        return selection.applicationTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    /// Shuts the picked apps. Same call in the app and in the monitor
    /// extension, so the two can never disagree about what "shielded" means.
    static func apply(to store: ManagedSettingsStore) {
        let selection = current
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    static func clear(from store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}
