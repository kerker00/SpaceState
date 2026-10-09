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

    /// The APNs environment of this build's signature, which decides where its token is valid:
    /// development-signed builds (also Release builds run from Xcode) get sandbox tokens,
    /// TestFlight, App Store and Developer ID builds production ones.
    private static let environment: PushEnvironment = SigningEnvironment.current

    /// - Parameter serviceURL: Defaults to `SpacePushURL` from the Info.plist, set per build configuration.
    init(serviceURL: URL? = StatusService.configuredServiceURL, defaults: UserDefaults = .standard) {
        client = serviceURL.map(SpacePushClient.configured)
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
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
            try await client.register(
                deviceToken: deviceToken,
                environment: Self.environment,
                subscriptions: subscriptions,
                platform: ClientIdentity.platform
            )
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

/// Reads `aps-environment` from the app's signature instead of guessing from the build
/// configuration: a Release build signed for development still gets sandbox tokens.
private enum SigningEnvironment {
    static var current: PushEnvironment {
        switch apsEnvironment {
        case "development": .sandbox
        case "production": .production
        default: fallback
        }
    }

    /// Used when the signature cannot be read.
    private static var fallback: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    #if os(macOS)
    private static var apsEnvironment: String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.aps-environment" as CFString, nil) as? String
    }
    #else
    /// Development and ad hoc builds embed their provisioning profile, a signed plist whose
    /// entitlements hold `aps-environment`. TestFlight and App Store builds have none.
    private static var apsEnvironment: String? {
        #if targetEnvironment(simulator)
        return "development"
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return "production"
        }
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let profile = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil
              ) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any]
        else { return nil }
        return entitlements["aps-environment"] as? String
        #endif
    }
    #endif
}
