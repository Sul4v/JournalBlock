import Foundation
import Observation
import UserNotifications

/// Daily notifications, one per block that asks for them.
///
/// Deliberately not AlarmKit. An alarm rings through silent mode and Focus and
/// takes over the screen — right for the one sitting that has to happen at the
/// hour it says, wrong for the four others. A block reminder is a notification:
/// it waits on the lock screen, and a day that gets away from someone doesn't
/// come with a siren attached. See `AlarmService` for the wake alarm.
@Observable
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    private(set) var isAuthorized = false
    private(set) var lastError: String?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    /// Every request this service owns, so a reschedule can clear its own
    /// notifications without touching anything else the app may add later.
    private static let prefix = "dawn.block."

    private init() {}

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            lastError = granted ? nil : "Notifications are switched off for \(AppConfig.appName)."
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Rebuilds the whole schedule from the blocks as they now stand.
    ///
    /// Wholesale rather than incremental on purpose: the alternative is
    /// tracking which block changed and how, and the failure mode of getting
    /// that wrong is a notification that fires at a time the user has already
    /// changed — which reads as the app ignoring them.
    func reschedule(for blocks: [JournalBlock]) async {
        let wanted = blocks.filter(\.remindersEnabled)

        center.removePendingNotificationRequests(
            withIdentifiers: blocks.map { Self.prefix + $0.id.uuidString }
        )
        guard !wanted.isEmpty else { return }

        if !isAuthorized {
            guard await requestAuthorization() else { return }
        }

        for block in wanted {
            let content = UNMutableNotificationContent()
            content.title = block.timeLabel
            content.body = Self.body(for: block)
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: block.hour, minute: block.minute),
                repeats: true
            )

            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: Self.prefix + block.id.uuidString,
                        content: content,
                        trigger: trigger
                    )
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Cancels everything this service owns. Used when the journal is wiped for
    /// a different account, where the previous user's schedule must not survive.
    func cancelAll() {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ids
            )
        }
    }

    /// Says what the block is, not that the app exists. A notification that
    /// reads "Don't forget to journal!" is the reason people switch these off.
    private static func body(for block: JournalBlock) -> String {
        switch block.hour {
        case 0..<5, 20...: "A few minutes to close the day."
        case 5..<11: "Your page is ready."
        case 11..<16: "Time to check in."
        default: "A few minutes, before the evening runs off."
        }
    }
}
