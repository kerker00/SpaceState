import SwiftUI

@main
struct SpaceStateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var directory = DirectoryStore()
    @Environment(\.scenePhase) private var scenePhase

    private var store: StatusStore { appDelegate.store }

    var body: some Scene {
        WindowGroup {
            Group {
                if appDelegate.onboarding.isComplete {
                    StatusView(store: store, directory: directory, push: appDelegate.push, navigation: appDelegate.navigation)
                } else {
                    OnboardingView(onboarding: appDelegate.onboarding, store: store,
                                   directory: directory, push: appDelegate.push)
                }
            }
                .onOpenURL { _ = appDelegate.navigation.open(url: $0) }
                .onChange(of: store.pushSubscriptions, initial: true) { _, subscriptions in
                    appDelegate.push.update(subscriptions: subscriptions)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Polling pauses in the background; catch up when the app comes back.
            if phase == .active {
                if appDelegate.onboarding.hasSelectedSpace { store.resumePolling() }
                appDelegate.navigation.resume()
                Task { await appDelegate.push.refreshAuthorization() }
            } else if phase == .background {
                store.pausePolling()
                appDelegate.navigation.pause()
            }
        }
    }
}
