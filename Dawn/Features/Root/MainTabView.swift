import SwiftUI

/// Only reachable once the morning pages are written.
struct MainTabView: View {
    @Environment(BackupController.self) private var backup
    @State private var selection: Destination

    enum Destination: Hashable { case today, entries, settings }

    private let settingsRoute: SettingsView.Route?

    init(start: Destination = .today, settingsRoute: SettingsView.Route? = nil) {
        _selection = State(initialValue: start)
        self.settingsRoute = settingsRoute
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon", value: Destination.today) {
                HomeView()
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
    }
}
