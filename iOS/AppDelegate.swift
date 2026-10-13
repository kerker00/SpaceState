import UIKit
import UserNotifications

/// Owns the app's state, receives the APNs device token and shows
/// notifications while the app is in the foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = StatusStore()
    let push = PushStore()

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        store.startPolling()
        push.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push.didFailToRegister(error)
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
        let endpoint = response.notification.request.content.userInfo["endpoint"] as? String
        await store.notificationReceived(endpoint: endpoint)
    }
}
