import ManagedSettings
import UserNotifications

/// What the two buttons on the shield do.
///
/// ## Why this posts a notification instead of just opening the app
///
/// A `ShieldActionDelegate` cannot open its containing app. The only thing it
/// is allowed to return is `.none`, `.close` or `.defer` — there is no
/// `open(url:)` here, `UIApplication` is unavailable to this extension type,
/// and `NSExtensionContext` is not offered either. Reaching `UIApplication`
/// through `NSClassFromString` and a performed selector does work, and is what
/// several shipping blockers do, but it is private API on an entitlement Apple
/// reviews by hand — a bad thing to stake this feature on.
///
/// So "Write it now" posts an immediate local notification carrying a deep
/// link and closes the shielded app. The user lands on the home screen with the
/// banner already there, and one tap opens JournalBlock on that block's page.
/// It is one extra tap than we'd like, and it is the reason the permission
/// primer asks for notifications *before* Screen Time: without notifications
/// this button can only bounce them to the home screen with no way back in.
final class ShieldActionHandler: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    // MARK: -

    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // Close either way. If the notification can't be posted the user is
            // still returned to the home screen, where the app icon is — which
            // is a worse route back but never a dead end.
            postHandoff { completionHandler(.close) }

        case .secondaryButtonPressed:
            // "Not now" closes the shielded app rather than deferring. `.defer`
            // leaves the shield standing on top of the app they were trying to
            // open, which reads as the button having done nothing.
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    /// An immediate notification whose tap opens the app at the owed block.
    private func postHandoff(then finish: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        let block = GateBridge.pendingBlock

        let content = UNMutableNotificationContent()
        content.title = block.map { "Your \($0.timeLabel) page" } ?? "Your page is waiting"
        content.body = "Tap to write it and get your apps back for the day."
        content.sound = .default
        if let block {
            content.userInfo = ["blockID": block.id.uuidString]
            content.targetContentIdentifier = GateBridge.deepLink(for: block.id).absoluteString
        }

        // nil trigger = deliver now. The shielded app is about to close, so the
        // banner arrives as the user lands on the home screen.
        let request = UNNotificationRequest(
            identifier: GateBridge.handoffNotificationID,
            content: content,
            trigger: nil
        )

        center.add(request) { _ in finish() }
    }
}
