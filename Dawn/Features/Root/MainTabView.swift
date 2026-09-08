import SwiftUI

/// Opens after setup, then after the morning pages on subsequent days.
struct MainTabView: View {
    @Environment(BackupController.self) private var backup
    @State private var selection: Destination

    enum Destination: Hashable { case today, entries, settings }

    private let settingsRoute: SettingsView.Route?
    private let isPreparingFirstMorning: Bool

    init(start: Destination = .today, settingsRoute: SettingsView.Route? = nil,
         isPreparingFirstMorning: Bool = false) {
        _selection = State(initialValue: start)
        self.settingsRoute = settingsRoute
        self.isPreparingFirstMorning = isPreparingFirstMorning
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon", value: Destination.today) {
                HomeView(isPreparingFirstMorning: isPreparingFirstMorning)
            }
            Tab("Entries", systemImage: "book.closed", value: Destination.entries) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: Destination.settings) {
                SettingsView(start: settingsRoute)
            }
            // A dot, not a banner. Backup breaking is rare enough that putting
            // it on the Today screen taxes every good morning to catch a bad
            // one — but it still has to be visible from anywhere without the
            // user going looking for it.
            .badge(backup.needsAttention ? Text("!") : nil)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.Palette.ember)
        // The tab is @State, so it survives backgrounding: without this, a
        // user who left the app on Settings and then pressed "Write it now"
        // on the shield came back to Settings.
        .onReceive(NotificationCenter.default.publisher(for: .dawnBlockHandoff)) { _ in
            withAnimation(Theme.Motion.gentle) { selection = .today }
        }
    }
}

extension Notification.Name {
    /// Posted when something outside the app sends the user to the block they
    /// owe: a tap on the shield's handoff notification in reminder mode, or the
    /// alarm's Stop button in alarm mode. `MainTabView` uses it to select
    /// Today; `HomeView` uses it to draw the eye to the block that is owed.
    ///
    /// Named for the errand rather than the sender, because there are two of
    /// them now and both want the identical arrival — the whole point of the
    /// two gate modes is that they summon you differently and then hand you to
    /// the same page.
    ///
    /// A notification rather than a route because the destination isn't a new
    /// screen — it is the screen the user is most likely already on, and the
    /// work is getting their attention onto one card of it.
    static let dawnBlockHandoff = Notification.Name("dawn.blockHandoff")
}
