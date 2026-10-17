import CoreLocation
import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import Testing
import UserNotifications

@Suite(.serialized)
@MainActor
struct OnboardingTests {
    private func entry(_ name: String = "Chosen", lat: Double? = 53, lon: Double? = 8) -> DirectoryEntry {
        DirectoryEntry(endpoint: URL(string: "https://\(name.lowercased()).invalid/status")!,
            info: SpaceInfo(name: name, location: .init(address: nil, latitude: lat, longitude: lon, timezone: nil)),
            lastSeen: nil)
    }

    private func status(_ fixture: PushFixture) -> StatusStore {
        StatusStore(service: StatusService(spacePush: nil, direct: StatusClient(load: { _ in
            Issue.record("Onboarding must not start a status request in this harness")
            throw URLError(.cancelled)
        })), defaults: fixture.defaults, reloadWidgets: { Issue.record("Unexpected widget reload") })
    }

    @Test func freshInstallAndInterruptedFirstStepRequireExplicitSelection() {
        let f = PushFixture(); defer { f.close() }
        let first = OnboardingStore(defaults: f.defaults)
        #expect(first.step == .space)
        #expect(!first.hasSelectedSpace)
        // Directory usage may report periods during a first run; that is not completion.
        f.defaults.set(["day": "2026-10-17"], forKey: "reportedPeriods")
        #expect(OnboardingStore(defaults: f.defaults).step == .space)
        first.finish()
        #expect(!first.isComplete)
    }

    @Test func existingPreferencesArePreservedWithoutFirstRun() {
        let f = PushFixture(); defer { f.close() }
        f.defaults.set("https://saved.invalid/status", forKey: "spaceEndpoint")
        f.defaults.set(true, forKey: "pushEnabled")
        #expect(OnboardingStore(defaults: f.defaults).isComplete)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == "https://saved.invalid/status")
        #expect(f.defaults.bool(forKey: "pushEnabled"))
    }

    @Test func existingDefaultSpaceInstallIsRecognizedByPriorUsage() {
        let f = PushFixture(); defer { f.close() }
        f.defaults.set(["day": "2026-10-16"], forKey: "reportedPeriods")
        #expect(OnboardingStore(defaults: f.defaults).isComplete)
    }

    @Test func confirmedSelectionResumesAtNotificationsAndFinishesOnce() {
        let f = PushFixture(); defer { f.close() }
        let setup = OnboardingStore(defaults: f.defaults)
        let store = status(f)
        setup.select(entry(), in: store)
        #expect(store.endpoint == entry().endpoint)
        let resumed = OnboardingStore(defaults: f.defaults)
        #expect(resumed.step == .notifications)
        #expect(resumed.selectedName == "Chosen")
        resumed.finish()
        resumed.select(entry("Other"), in: store)
        #expect(store.endpoint == entry().endpoint)
        #expect(OnboardingStore(defaults: f.defaults).isComplete)
    }

    @Test func explicitlyChoosingLegacyDefaultStillPersistsIt() {
        let f = PushFixture(); defer { f.close() }
        let setup = OnboardingStore(defaults: f.defaults)
        let store = status(f)
        let mainframe = DirectoryEntry(endpoint: Mainframe.spaceAPIEndpoint, info: SpaceInfo(name: "Mainframe"), lastSeen: nil)
        setup.select(mainframe, in: store)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == Mainframe.spaceAPIEndpoint.absoluteString)
        #expect(OnboardingStore(defaults: f.defaults).step == .notifications)
    }

    @Test func nearestIgnoresMissingInvalidAndNonfiniteCoordinates() {
        let valid = entry("Valid")
        let entries = [entry("Missing", lat: nil), entry("BadLat", lat: 91), entry("BadLon", lon: -181),
                       entry("Nan", lat: .nan), entry("Infinite", lon: .infinity), valid]
        #expect(OnboardingStore.nearest(in: entries, to: CLLocation(latitude: 53, longitude: 8)) == valid)
        #expect(OnboardingStore.nearest(in: Array(entries.dropLast()), to: CLLocation(latitude: 53, longitude: 8)) == nil)
    }

    @Test func nearestHandlesAntimeridianAndZeroCoordinates() {
        let nearby = entry("Across", lat: 0, lon: -179.9)
        let far = entry("Far", lat: 0, lon: 170)
        #expect(OnboardingStore.nearest(in: [far, nearby], to: CLLocation(latitude: 0, longitude: 179.9)) == nearby)
        let zero = entry("Zero", lat: 0, lon: 0)
        #expect(OnboardingStore.nearest(in: [far, zero], to: CLLocation(latitude: 0, longitude: 0)) == zero)
    }

    @Test func nearestIsDeterministicAndDoesNotSelectAnything() {
        let f = PushFixture(); defer { f.close() }
        let setup = OnboardingStore(defaults: f.defaults)
        let a = entry("A"); let b = entry("B")
        #expect(OnboardingStore.nearest(in: [b, a], to: CLLocation(latitude: 53, longitude: 8)) == a)
        #expect(OnboardingStore.nearest(in: [], to: CLLocation(latitude: 53, longitude: 8)) == nil)
        #expect(OnboardingStore.nearest(in: [a], to: CLLocation(latitude: 100, longitude: 8)) == nil)
        #expect(setup.step == .space)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == nil)
    }

    @Test func skippingNotificationsDoesNotAskOrRegister() async {
        let f = PushFixture(); defer { f.close() }
        let setup = OnboardingStore(defaults: f.defaults)
        setup.select(entry(), in: status(f))
        await setup.skipNotifications(using: f.store)
        await f.store.refreshAuthorization()
        #expect(setup.isComplete)
        #expect(!f.store.isEnabled)
        #expect(f.notifications.promptRequests == 0)
        #expect(f.notifications.tokenRequests == 0)
        #expect(f.transport.requests.isEmpty)
        // Resume after an interrupted activation: the saved intent is cleared too.
        let resumed = PushFixture(); defer { resumed.close() }
        let interrupted = OnboardingStore(defaults: resumed.defaults)
        interrupted.select(entry(), in: status(resumed))
        resumed.defaults.set(true, forKey: "pushEnabled")
        let resumedPush = resumed.makeStore()
        await OnboardingStore(defaults: resumed.defaults).skipNotifications(using: resumedPush)
        #expect(!resumedPush.isEnabled)
        #expect(!resumed.defaults.bool(forKey: "pushEnabled"))
        #expect(resumed.notifications.promptRequests == 0)
        #expect(resumed.transport.requests.isEmpty)
    }

    @Test func permissionDenialCompletesSetupWithoutRegistration() async throws {
        let f = PushFixture(); defer { f.close() }
        f.notifications.authorization = .notDetermined
        f.notifications.holdPrompt = true
        let setup = OnboardingStore(defaults: f.defaults)
        let store = status(f)
        setup.select(entry(), in: store)
        let action = Task { await setup.enableNotifications(using: f.store, store: store) }
        try await eventually { f.notifications.promptRequests == 1 }
        // A second action while the system prompt is open must do nothing.
        await setup.enableNotifications(using: f.store, store: store)
        #expect(!setup.isComplete)
        f.notifications.answerPrompt(false)
        await action.value
        #expect(setup.isComplete)
        #expect(f.store.status == .denied)
        #expect(f.notifications.promptRequests == 1)
        #expect(f.notifications.tokenRequests == 0)
        #expect(f.transport.requests.isEmpty)
    }

    @Test func grantedPermissionRegistersOnlyConfirmedSpace() async throws {
        let f = PushFixture(); defer { f.close() }
        f.notifications.authorization = .notDetermined
        let setup = OnboardingStore(defaults: f.defaults)
        let store = status(f)
        setup.select(entry(), in: store)
        await setup.enableNotifications(using: f.store, store: store)
        #expect(setup.isComplete)
        #expect(f.notifications.promptRequests == 1)
        #expect(f.notifications.tokenRequests == 1)
        f.store.didRegister(deviceToken: f.token)
        try await eventually { f.transport.requests.count == 1 }
        let body = try #require(f.transport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let subscriptions = try #require(json["subscriptions"] as? [[String: Any]])
        #expect(subscriptions.count == 1)
        #expect(subscriptions.first?["endpoint"] as? String == entry().endpoint.absoluteString)
        f.transport.respond(0)
        try await eventually { f.store.status == .registered }
        await setup.enableNotifications(using: f.store, store: store)
        #expect(f.notifications.promptRequests == 1)
    }

    @Test func previouslyDeniedPermissionNeverRepeatsSystemPrompt() async {
        let f = PushFixture(); defer { f.close() }
        f.notifications.authorization = .denied
        let setup = OnboardingStore(defaults: f.defaults)
        let store = status(f)
        setup.select(entry(), in: store)
        await setup.enableNotifications(using: f.store, store: store)
        #expect(setup.isComplete)
        #expect(f.store.status == .denied)
        #expect(f.notifications.promptRequests == 0)
        #expect(f.notifications.tokenRequests == 0)
    }
}
