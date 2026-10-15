import AppKit
import SwiftUI
import UserNotifications

/// Owns the app's state, receives the APNs device token, and shows the status
/// window when the user clicks a notification.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    let store = StatusStore()
    let push = PushStore()
    let navigation = SpaceNavigation()
    private var statusWindow: NSWindow?
    private var detailsWindow: NSWindow?
    private var targetWindow: NSWindow?

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

    func applicationDidBecomeActive(_ notification: Notification) {
        push.start()
        Task { await store.refresh() }
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
        let endpoint = notification.request.content.userInfo["endpoint"] as? String
        await store.notificationReceived(endpoint: endpoint)
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let endpoint = response.notification.request.content.userInfo["endpoint"] as? String
        let room = response.notification.request.content.userInfo["room"] as? String
        await openNotification(endpoint: endpoint, room: room)
    }

    private func openNotification(endpoint: String?, room: String?) {
        guard let target = SpaceDestination.notification(endpoint: endpoint, room: room, fallback: store.endpoint) else { return }
        store.notificationReceived(endpoint: target.endpoint.absoluteString)
        openTarget(target)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let target = urls.lazy.compactMap({ SpaceDestination(url: $0) }).first else { return }
        openTarget(target)
    }

    private func openTarget(_ target: SpaceDestination) {
        navigation.open(target)
        guard let destination = navigation.destination else { return }
        let root = SpaceTargetView(destination: destination) { [weak self] in self?.targetWindow?.performClose(nil) }
            .id(destination.id)
        let controller = NSHostingController(rootView: root)
        let window: NSWindow
        if let existing = targetWindow {
            window = existing
            window.contentViewController = controller
        } else {
            window = NSWindow(contentViewController: controller)
        }
        window.title = "SpaceState"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 480, height: 500)
        if targetWindow == nil {
            window.setContentSize(NSSize(width: 600, height: 700))
            window.center()
        }
        repairContentSize(window, minimum: NSSize(width: 480, height: 500))
        targetWindow = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === targetWindow {
            navigation.close()
            targetWindow = nil
        }
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: StatusPanel(store: store, showDetails: showDetailsWindow)))
        window.title = "SpaceState"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 640))
        window.contentMinSize = NSSize(width: 380, height: 640)
        window.center()
        window.setFrameAutosaveName("StatusWindow")
        repairContentSize(window, minimum: NSSize(width: 380, height: 640))
        return window
    }

    /// A regular window keeps contacts and feeds available after the menu bar closes.
    func showDetailsWindow() {
        guard store.info != nil else { return }
        let window = detailsWindow ?? makeDetailsWindow()
        detailsWindow = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeDetailsWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SpaceDetailsWindow(store: store)))
        window.title = String(localized: "Space details")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 500)
        window.setContentSize(NSSize(width: 600, height: 700))
        window.center()
        window.setFrameAutosaveName("SpaceDetailsWindow")
        repairContentSize(window, minimum: NSSize(width: 480, height: 500))
        return window
    }

    /// Also recover if a previous version saved a collapsed window frame.
    private func repairContentSize(_ window: NSWindow, minimum: NSSize) {
        let size = window.contentRect(forFrameRect: window.frame).size
        if size.width < minimum.width || size.height < minimum.height {
            window.setContentSize(NSSize(width: max(size.width, minimum.width),
                                         height: max(size.height, minimum.height)))
        }
    }
}

private struct SpaceDetailsWindow: View {
    var store: StatusStore

    var body: some View {
        NavigationStack {
            if let info = store.info {
                SpaceDetailsView(info: info, timing: store.observationTiming, lastReadFailed: store.lastError != nil)
            }
        }
        .frame(minWidth: 480, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 700, maxHeight: .infinity)
    }
}
