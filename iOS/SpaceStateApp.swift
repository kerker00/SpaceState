import SwiftUI

@main
struct SpaceStateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var directory = DirectoryStore()
    @Environment(\.scenePhase) private var scenePhase

    private var store: StatusStore { appDelegate.store }

    var body: some Scene {
        WindowGroup {
            StatusView(store: store, directory: directory, push: appDelegate.push)
                .onChange(of: store.pushSubscriptions, initial: true) { _, subscriptions in
                    appDelegate.push.update(subscriptions: subscriptions)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Polling pauses in the background; catch up when the app comes back.
            if phase == .active {
                Task { await store.refresh() }
            }
        }
    }
}
