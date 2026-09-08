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

    /// The `ManagedSettingsStore` the gate's shields live in. The app and the
    /// monitor extension write to the same store, so this name has to be one
    /// constant — two stores with different names means the app clears a shield
    /// the extension applied, or worse, doesn't.
    static let storeName = "dawn.morningGate"

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

    /// Written by the app whenever the gate opens or closes. `nil` means the
    /// phone is the user's — any shield still on screen is stale and should
    /// let them through.
    static var pendingBlock: PendingBlock? {
        get {
            guard let data = defaults?.data(forKey: Key.pendingBlock) else { return nil }
            return try? JSONDecoder().decode(PendingBlock.self, from: data)
        }
        set {
            guard let defaults else { return }
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Key.pendingBlock)
                return
            }
            defaults.set(data, forKey: Key.pendingBlock)
        }
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
        static let pendingBlock = "gate.pendingBlock"
        static let selection = "gate.shieldSelection"
        static let shieldingEnabled = "gate.shieldingEnabled"
    }
}
