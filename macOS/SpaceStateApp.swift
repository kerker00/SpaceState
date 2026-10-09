import SwiftUI

@main
struct SpaceStateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var directory = DirectoryStore()

    /// Shared with the status window the app delegate opens for notification clicks.
    private var store: StatusStore { appDelegate.store }

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(store: store)
        } label: {
            Label {
                Text(store.status.title)
            } icon: {
                Image(systemName: store.status.symbolName)
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: store.pushSubscriptions, initial: true) { _, subscriptions in
            appDelegate.push.update(subscriptions: subscriptions)
        }

        Settings {
            SettingsView(store: store, directory: directory, push: appDelegate.push)
        }
    }
}
