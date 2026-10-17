import SwiftUI

@main
struct SpaceStateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Shared with the status window the app delegate opens for notification clicks.
    private var store: StatusStore { appDelegate.store }

    var body: some Scene {
        MenuBarExtra {
            if appDelegate.onboarding.isComplete {
                StatusPanel(store: store, showDetails: appDelegate.showDetailsWindow)
                    .environment(\.spaceAppearance, .menuBar)
                    .containerBackground(.regularMaterial, for: .window)
            } else {
                Button("Set up SpaceState") { appDelegate.showOnboardingWindow() }
                    .padding()
            }
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
            if appDelegate.onboarding.isComplete {
                SettingsView(store: store, directory: appDelegate.directory, push: appDelegate.push)
            } else {
                OnboardingView(onboarding: appDelegate.onboarding, store: store,
                               directory: appDelegate.directory, push: appDelegate.push)
                    .frame(minWidth: 480, minHeight: 560)
            }
        }
        .defaultSize(width: 520, height: 480)
        .windowResizability(.contentMinSize)
    }
}
