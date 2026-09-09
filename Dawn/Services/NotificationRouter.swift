import Foundation
import UIKit
import UserNotifications

/// Puts the user in front of the block they owe when they tap a notification.
///
/// Nothing did this before. `DawnApp.onOpenURL` reads the deep link the shield
/// writes into `targetContentIdentifier`, but a notification tap never reaches
/// that hook — `onOpenURL` fires for URLs handed to the scene, and a tap is
/// delivered here instead. Without a delegate the system foregrounds the app
/// and stops: someone who pressed "Write it now" on the shield, or tapped their
/// block reminder, came back to whatever tab they had left open, with nothing
/// pointing at the sitting that had come due.
///
/// Every notification this app posts leads to the same place, so this doesn't
/// read the payload to decide where to go — see `Notification.Name.dawnBlockHandoff`,
/// which the alarm's Stop button posts for the identical reason.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// A tap that has been taken but not yet acted on.
    ///
    /// The tap arrives *before* the scene is active — the app is still being
    /// resumed — and posting from there drove SwiftUI into a layout pass that
    /// made UIKit commit a CATransaction for a background event, which throws
    /// and takes the app down with it. So the tap is recorded here and spent
    /// once there is a live scene to spend it on. See `deliverPendingHandoff`.
    @MainActor private static var hasPendingHandoff = false

    override private init() { super.init() }

    /// Must run before the app finishes launching, or a tap that launched the
    /// app cold is delivered before there is a delegate to take it. Called from
    /// `DawnApp.init`.
    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// A block reminder that lands while the app is open still shows itself.
    ///
    /// iOS suppresses banners for the frontmost app by default, which is wrong
    /// here: the banner is the only thing that names *which* sitting has just
    /// come due, and swallowing it because the user happened to be reading last
    /// week's entries loses that.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// The completion-handler form, deliberately, rather than the `async` one.
    ///
    /// Both exist and the `async` spelling is the tidier read, but the compiler
    /// bridges it by calling UIKit's completion handler wherever the async
    /// function happens to finish — which is a Swift concurrency thread, not the
    /// main one. UIKit answers that handler by updating the scene snapshot and
    /// state-restoration archive, work that must happen on the main thread, and
    /// throws an exception when it doesn't. The result was an app that died on
    /// every notification tap that arrived while it was in the background: the
    /// exact case this router was added to fix.
    ///
    /// Nothing about the isolation of the *body* saves it — the throw is in the
    /// handler, after the body has run — so the shape of the method is the fix.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // A swipe-away is not a request to be taken anywhere.
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }

        // The shield's handoff banner has done its job the moment it is tapped,
        // and one left sitting in Notification Centre offers a second door into
        // a page that may by then be written.
        center.removeDeliveredNotifications(withIdentifiers: [GateBridge.handoffNotificationID])

        // On the main thread for the reason above: the handler is UIKit's cue to
        // do main-thread-only work.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Self.recordHandoff() }
            completionHandler()
        }
    }

    /// Takes the tap. Spends it immediately only if there is already a live
    /// scene — a banner tapped while the app is open, which is safe and is the
    /// one case that was never broken.
    @MainActor
    private static func recordHandoff() {
        hasPendingHandoff = true
        guard UIApplication.shared.applicationState == .active else { return }
        deliverPendingHandoff()
    }

    /// Spends a recorded tap. Called by `RootView` when the scene goes active,
    /// which is the first moment SwiftUI can be driven safely.
    ///
    /// Also drains on the *initial* active phase, so a tap that cold-launched
    /// the app doesn't leave a charge sitting in here — `HomeView.onAppear`
    /// has already revealed the block by then, and an unspent tap would fire
    /// on some unrelated return to the app half an hour later.
    @MainActor
    static func deliverPendingHandoff() {
        guard hasPendingHandoff else { return }
        hasPendingHandoff = false
        NotificationCenter.default.post(name: .dawnBlockHandoff, object: nil)
    }
}
