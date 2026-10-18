import Foundation
import SpacePushClient
import Testing
import UserNotifications

@Suite(.serialized)
@MainActor
struct PushStoreFailureTests {
    @Test func failedPermissionPromptIsVisibleAndRetried() async throws {
        let f = PushFixture(); defer { f.close() }
        f.notifications.authorization = .notDetermined
        f.notifications.promptError = URLError(.cannotConnectToHost)
        f.store.update(subscriptions: [f.a])
        await f.store.setEnabled(true)
        if case .failed = f.store.status {} else { Issue.record("prompt failure must be visible") }
        try await eventually { f.retry.count == 1 }
        #expect(f.notifications.tokenRequests == 0)
        f.notifications.promptError = nil
        f.notifications.authorization = .authorized
        f.retry.fire()
        try await eventually { f.notifications.tokenRequests == 1 }
        #expect(f.store.status == .registering)
    }

    @Test func failedAPNsRegistrationIsVisibleAndRetried() async throws {
        let f = PushFixture(); defer { f.close() }
        f.store.update(subscriptions: [f.a])
        await f.store.setEnabled(true)
        #expect(f.notifications.tokenRequests == 1)
        f.store.didFailToRegister(URLError(.notConnectedToInternet))
        if case .failed = f.store.status {} else { Issue.record("APNs failure must be visible") }
        try await eventually { f.retry.count == 1 }
        f.retry.fire()
        try await eventually { f.notifications.tokenRequests == 2 }
        #expect(f.transport.requests.isEmpty)
    }

    @Test func subscriptionsAreDeduplicatedAndOrderedBeforeTheyAreSent() async throws {
        let f = PushFixture(); defer { f.close() }
        f.store.update(subscriptions: [f.b, f.a, f.a])
        await f.store.setEnabled(true)
        f.store.didRegister(deviceToken: f.token)
        try await eventually { f.transport.requests.count == 1 }
        let body = try #require(f.transport.requests[0].httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let a = try #require(body.range(of: "a.invalid"))
        let b = try #require(body.range(of: "b.invalid"))
        #expect(a.lowerBound < b.lowerBound)
        #expect(body.components(separatedBy: "a.invalid").count == 2)
        f.transport.respond(0)
        try await eventually { f.store.status == .registered }

        // The same set in another order is not a change.
        f.store.update(subscriptions: [f.a, f.b])
        for _ in 0..<20 { await Task.yield() }
        #expect(f.transport.requests.count == 1)
        f.store.update(subscriptions: [f.a, f.room])
        try await eventually { f.transport.requests.count == 2 }
    }

    @Test func roomsOfTheSameSpaceSortAfterTheSpaceItself() async throws {
        let f = PushFixture(); defer { f.close() }
        f.store.update(subscriptions: [f.room, f.a])
        await f.store.setEnabled(true)
        f.store.didRegister(deviceToken: f.token)
        try await eventually { f.transport.requests.count == 1 }
        let data = try #require(f.transport.requests[0].httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let subscriptions = try #require(json["subscriptions"] as? [[String: String]])
        #expect(subscriptions.map { $0["room"] } == [nil, "lab"])
        #expect(subscriptions.map { $0["endpoint"] } == [f.a.endpoint.absoluteString, f.a.endpoint.absoluteString])
    }

    @Test func manualRetryRechecksPermissionAndRequestsAFreshToken() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.registered()
        #expect(f.notifications.tokenRequests == 1)
        f.store.retry()
        try await eventually { f.notifications.tokenRequests == 2 }
        #expect(f.notifications.promptRequests == 0)
    }

    @Test func missingServiceIsReportedInsteadOfRegistering() async throws {
        let f = PushFixture(); defer { f.close() }
        let notifications = f.notifications
        let retry = f.retry
        let store = PushStore(client: nil, defaults: f.defaults, system: .init(
            authorization: { await notifications.settings() },
            requestAuthorization: { try await notifications.request() },
            requestToken: { notifications.requestToken() },
            waitForRetry: { try await retry.sleep() }
        ))
        store.update(subscriptions: [f.a])
        await store.setEnabled(true)
        store.didRegister(deviceToken: f.token)
        try await eventually { if case .failed = store.status { return true }; return false }
        #expect(store.status == .failed(String(localized: "Push service is not configured.")))
        #expect(f.transport.requests.isEmpty)
    }
}

extension PushFixture {
    var room: PushSubscription { PushSubscription(endpoint: a.endpoint, room: "lab") }
}
