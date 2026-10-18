import UIKit
import UserNotifications

/// Owns the app's state, receives the APNs device token and shows
/// notifications while the app is in the foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let onboarding = OnboardingStore()
    let store = StatusStore()
    let push = PushStore()
    let navigation = SpaceNavigation()

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if onboarding.hasSelectedSpace { store.startPolling() }
        push.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push.didFailToRegister(error)
    }

    // Completion-handler variants: the async ones return to UIKit off the main
    // thread, which crashes when a notification is opened from the lock screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let endpoint = notification.request.content.userInfo["endpoint"] as? String
        Task { @MainActor in
            self.store.notificationReceived(endpoint: endpoint)
            completionHandler([.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            DispatchQueue.main.async(execute: completionHandler)
            return
        }
        let endpoint = response.notification.request.content.userInfo["endpoint"] as? String
        let room = response.notification.request.content.userInfo["room"] as? String
        Task { @MainActor in
            self.openNotification(endpoint: endpoint, room: room)
            completionHandler()
        }
    }

    @MainActor
    private func openNotification(endpoint: String?, room: String?) {
        guard let target = SpaceDestination.notification(endpoint: endpoint, room: room, fallback: store.endpoint) else { return }
        store.notificationReceived(endpoint: target.endpoint.absoluteString)
        navigation.open(target)
    }
}
