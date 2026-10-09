import AppKit
import SwiftUI
import UserNotifications

/// Owns the app's state, receives the APNs device token, and shows the status
/// window when the user clicks a notification.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = StatusStore()
    let push = PushStore()
    private var statusWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DockIcon.isVisible {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        UNUserNotificationCenter.current().delegate = self
        store.startPolling()
        push.start()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push.didFailToRegister(error)
    }

    /// Clicking the Dock icon shows the status window; otherwise macOS would
    /// bring up the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusWindow()
        return false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await showStatusWindow()
    }

    /// The menu bar panel cannot be opened from code, so a notification click
    /// opens the same view in a regular window.
    func showStatusWindow() {
        let window = statusWindow ?? makeStatusWindow()
        statusWindow = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeStatusWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: StatusPanel(store: store)))
        window.title = "SpaceState"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("StatusWindow")
        return window
    }
}
