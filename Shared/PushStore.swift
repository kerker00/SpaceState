import Foundation
import Observation
import SpacePushClient
import UserNotifications

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reconciles the latest notification preference with one ordered stream of
/// server writes. An in-flight write finishes before a compensating write starts.
@MainActor
@Observable
final class PushStore {
    enum Status: Equatable {
        case off
        case denied
        case registering
        case registered
        case failed(String)
    }

    /// Injectable system operations keep regressions away from APNs and permission dialogs.
    struct NotificationSystem {
        var authorization: () async -> UNAuthorizationStatus
        var requestAuthorization: () async throws -> Bool
        var requestToken: () -> Void
        var waitForRetry: () async throws -> Void

        static var live: Self {
            Self(
                authorization: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
                requestAuthorization: {
                    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                },
                requestToken: {
                    #if os(macOS)
                    NSApplication.shared.registerForRemoteNotifications()
                    #else
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                },
                waitForRetry: { try await Task.sleep(for: .seconds(5)) }
            )
        }
    }

    private(set) var status: Status = .off
    private(set) var isEnabled: Bool

    @ObservationIgnored private var deviceToken: Data?
    @ObservationIgnored private var subscriptions: [PushSubscription]?
    @ObservationIgnored private var registered: Registration?
    @ObservationIgnored private var possibleTokens: Set<Data>
    @ObservationIgnored private let client: SpacePushClient?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let system: NotificationSystem
    @ObservationIgnored private var authorizationAllowed: Bool?
    @ObservationIgnored private var authorizationRevision = 0
    @ObservationIgnored private var desiredRevision = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private struct Registration: Equatable {
        var deviceToken: Data
        var subscriptions: [PushSubscription]
    }

    private enum Target {
        case waiting
        case remove
        case register(Registration)
    }

    private enum Retry {
        case reconcile
        case system
    }

    private static let enabledKey = "pushEnabled"
    private static let possibleTokensKey = "pushTokensPendingCleanup"
    private static let environment: PushEnvironment = SigningEnvironment.current

    convenience init(serviceURL: URL? = StatusService.configuredServiceURL, defaults: UserDefaults = .standard) {
        self.init(client: serviceURL.map(SpacePushClient.configured), defaults: defaults, system: .live)
    }

    init(client: SpacePushClient?, defaults: UserDefaults, system: NotificationSystem) {
        self.client = client
        self.defaults = defaults
        self.system = system
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        possibleTokens = Set(defaults.array(forKey: Self.possibleTokensKey) as? [Data] ?? [])
    }

    /// Launch/foreground checks never show a permission dialog. Disabled apps still
    /// retry pending cleanup; fresh APNs callbacks, not saved tokens, enable PUTs.
    func start() {
        Task { [weak self] in await self?.refreshAuthorization() }
    }

    func refreshAuthorization() async {
        guard isEnabled else { changed(); return }
        authorizationRevision += 1
        let revision = authorizationRevision
        authorizationAllowed = nil
        registered = nil // Renew after launch or returning from the background.
        status = .registering
        changed()
        await checkAuthorization(prompt: false, revision: revision)
    }

    func setEnabled(_ enabled: Bool) async {
        authorizationRevision += 1
        let revision = authorizationRevision
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        authorizationAllowed = nil
        registered = nil
        status = enabled ? .registering : .off
        changed()
        guard enabled else { return }
        await checkAuthorization(prompt: true, revision: revision)
    }

    private func checkAuthorization(prompt: Bool, revision: Int) async {
        let authorization = await system.authorization()
        guard revision == authorizationRevision, isEnabled else { return }
        do {
            let allowed: Bool
            switch authorization {
            case .authorized, .provisional, .ephemeral: allowed = true
            case .notDetermined where prompt: allowed = try await system.requestAuthorization()
            default: allowed = false
            }
            guard revision == authorizationRevision, isEnabled else { return }
            authorizationAllowed = allowed
            status = allowed ? .registering : .denied
            changed()
            if allowed { system.requestToken() }
        } catch {
            guard revision == authorizationRevision, isEnabled else { return }
            status = .failed(error.localizedDescription)
            scheduleRetry(.system)
        }
    }

    func didRegister(deviceToken: Data) {
        self.deviceToken = deviceToken
        remember(deviceToken)
        changed()
    }

    func didFailToRegister(_ error: any Error) {
        guard isEnabled, authorizationAllowed == true else { return }
        status = .failed(error.localizedDescription)
        scheduleRetry(.system)
    }

    func update(subscriptions: [PushSubscription]) {
        let normalized = Array(Set(subscriptions)).sorted {
            let lhs = ($0.endpoint.absoluteString, $0.room ?? "")
            let rhs = ($1.endpoint.absoluteString, $1.room ?? "")
            return lhs < rhs
        }
        guard normalized != self.subscriptions else { return }
        self.subscriptions = normalized
        changed()
    }

    /// Immediate retry for settings; the automatic retry uses the same latest intent.
    func retry() { start() }

    private var target: Target {
        guard isEnabled else { return .remove }
        if authorizationAllowed == false || subscriptions?.isEmpty == true { return .remove }
        guard authorizationAllowed == true, let deviceToken, let subscriptions else { return .waiting }
        return .register(Registration(deviceToken: deviceToken, subscriptions: subscriptions))
    }

    private func changed() {
        desiredRevision += 1
        retryTask?.cancel()
        retryTask = nil
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.reconcile() }
    }

    private func reconcile() async {
        defer { worker = nil }
        while true {
            let wanted = target
            let keep: Data?
            switch wanted {
            case .waiting: return
            case .remove: keep = nil
            case .register(let registration): keep = registration.deviceToken
            }
            let obsolete = possibleTokens.filter { $0 != keep }.sorted { $0.lexicographicallyPrecedes($1) }.first
            if obsolete == nil {
                switch wanted {
                case .remove:
                    status = isEnabled && authorizationAllowed == false ? .denied : .off
                    return
                case .register(let registration) where registration == registered:
                    status = .registered
                    return
                default: break
                }
            }
            guard let client else {
                status = .failed(String(localized: "Push service is not configured."))
                return
            }
            if case .register = wanted { status = .registering }
            let revision = desiredRevision
            do {
                if let obsolete {
                    try await client.unregister(deviceToken: obsolete)
                    possibleTokens.remove(obsolete)
                    saveTokens()
                    if registered?.deviceToken == obsolete { registered = nil }
                } else if case .register(let registration) = wanted {
                    // A timeout can still mean the server accepted this token. Keep
                    // it until a successful DELETE, including across an app restart.
                    remember(registration.deviceToken)
                    try await client.register(
                        deviceToken: registration.deviceToken,
                        environment: Self.environment,
                        subscriptions: registration.subscriptions,
                        platform: ClientIdentity.platform
                    )
                    registered = registration
                }
                // Read the latest target again instead of publishing a stale result.
            } catch {
                registered = nil
                guard revision == desiredRevision else { continue }
                status = .failed(error.localizedDescription)
                scheduleRetry(.reconcile)
                return
            }
        }
    }

    private func remember(_ token: Data) {
        possibleTokens.insert(token)
        saveTokens()
    }

    private func saveTokens() {
        defaults.set(Array(possibleTokens), forKey: Self.possibleTokensKey)
    }

    private func scheduleRetry(_ action: Retry) {
        retryTask?.cancel()
        let revision = desiredRevision
        let wait = system.waitForRetry
        retryTask = Task { [weak self] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, let self, revision == self.desiredRevision else { return }
            self.retryTask = nil
            switch action {
            case .reconcile: self.changed()
            case .system: await self.refreshAuthorization()
            }
        }
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
