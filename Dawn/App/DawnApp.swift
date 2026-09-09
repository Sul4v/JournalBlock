import SwiftUI
import SwiftData
import UserNotifications

@main
struct DawnApp: App {
    private let container: ModelContainer
    private let store: JournalStore
    @State private var prefs = Preferences.shared
    @State private var shield = ShieldService.shared
    @State private var auth = AuthController()
    @State private var subs = SubscriptionController()
    @State private var backup = BackupController()

    init() {
        do {
            container = try ModelContainer(
                for: JournalEntry.self, JournalPrompt.self, PromptAnswer.self,
                JournalBlock.self
            )
        } catch {
            // A journal that can't open its own storage has nothing to show.
            // Fall back to memory so the app still launches and can report it.
            container = try! ModelContainer(
                for: JournalEntry.self, JournalPrompt.self, PromptAnswer.self,
                JournalBlock.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        GoogleSignInService.configure()
        // Before the scene exists: a tap that launches the app cold is delivered
        // as soon as launching finishes, and a delegate set any later misses it.
        NotificationRouter.shared.register()

        store = JournalStore(context: container.mainContext)
        store.prepareLibrary()
        #if DEBUG
        DebugHarness.seedSampleData(into: store)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.journalStore, store)
                .environment(prefs)
                .environment(shield)
                .environment(auth)
                .environment(subs)
                .environment(backup)
                .tint(Theme.Palette.ember)
                // nil under `.system`, which hands the choice back to iOS
                // and keeps following it if the user flips appearance
                // while Dawn is open.
                .preferredColorScheme(prefs.appearance.colorScheme)
                // Backup follows whoever is signed in: it has to pick up the
                // key on sign-in and drop it on sign-out, and the auth state is
                // the only thing that knows when either happened.
                .task(id: auth.user?.id) {
                    if let user = auth.user {
                        // Before anything can render the journal: if this phone
                        // was last used by a different account, that account's
                        // entries must not be visible — or silently absorbed
                        // into this one's backup.
                        LocalOwnership.claim(user.id, store: store, prefs: prefs)
                        await backup.refresh(for: user)
                        try? await backup.sync(store: store)
                    } else {
                        backup.signOut()
                    }
                }
                .onOpenURL { url in
                    // A tap on the shield's handoff notification. The block
                    // it names is the one the gate is already holding, so there
                    // is no destination to compute — but there is a tab to
                    // choose. Someone who just pressed "Write it now" must land
                    // on Today looking at the sitting they owe, not on whatever
                    // tab they happened to leave open last time.
                    //
                    // This also has to claim the URL before the auth handler
                    // below treats it as a Supabase callback, and clear the
                    // banner the shield left behind.
                    if GateBridge.blockID(fromDeepLink: url) != nil {
                        UNUserNotificationCenter.current()
                            .removeDeliveredNotifications(
                                withIdentifiers: [GateBridge.handoffNotificationID]
                            )
                        NotificationCenter.default.post(name: .dawnBlockHandoff, object: nil)
                        return
                    }
                    // Google owns its own scheme; everything else is a
                    // Supabase confirmation or recovery link.
                    if GoogleSignInService.handle(url) { return }
                    Task { await auth.handleCallback(url) }
                }
        }
        .modelContainer(container)
    }
}
