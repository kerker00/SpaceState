import Foundation
import Observation
import SpacePushClient
import UserNotifications

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Asks for permission, receives the device token and keeps the device's
/// registration with SpacePush in line with the selected subscriptions.
@Observable
final class PushStore {
    enum Status: Equatable {
        case off
        case denied
        case registering
        case registered
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var isEnabled: Bool

    private var deviceToken: Data?
    private var subscriptions: [PushSubscription] = []
    private var registered: Registration?
    private let client: SpacePushClient?
    private let defaults: UserDefaults

    private struct Registration: Equatable {
        var deviceToken: Data
        var subscriptions: [PushSubscription]
    }

    private static let enabledKey = "pushEnabled"

    /// Builds run from Xcode get sandbox tokens, TestFlight and App Store builds production ones.
    private static let environment: PushEnvironment = {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }()

    /// - Parameter serviceURL: Defaults to `SpacePushURL` from the Info.plist, set per build configuration.
    init(serviceURL: URL? = PushStore.configuredServiceURL, defaults: UserDefaults = .standard) {
        client = serviceURL.map { SpacePushClient(baseURL: $0) }
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    static var configuredServiceURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SpacePushURL") as? String).flatMap(URL.init(string:))
    }

    /// Requests a device token at launch if notifications were turned on before.
    func start() {
        guard isEnabled else { return }
        status = .registering
        registerForRemoteNotifications()
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                status = .denied
                return
            }
            isEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
            status = .registering
            registerForRemoteNotifications()
        } else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            status = .off
            if let deviceToken, let client {
                try? await client.unregister(deviceToken: deviceToken)
            }
            registered = nil
        }
    }

    func didRegister(deviceToken: Data) {
        self.deviceToken = deviceToken
        Task { await sync() }
    }

    func didFailToRegister(_ error: any Error) {
        status = .failed(error.localizedDescription)
    }

    func update(subscriptions: [PushSubscription]) {
        self.subscriptions = subscriptions
        Task { await sync() }
    }

    /// Sends the registration whenever the token or the subscriptions changed.
    /// SpacePush expires registrations that are not renewed, and every launch renews it.
    private func sync() async {
        guard isEnabled, let client, let deviceToken, !subscriptions.isEmpty else { return }
        let registration = Registration(deviceToken: deviceToken, subscriptions: subscriptions)
        guard registration != registered else { return }
        do {
            try await client.register(deviceToken: deviceToken, environment: Self.environment, subscriptions: subscriptions)
            registered = registration
            status = .registered
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func registerForRemoteNotifications() {
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
