import Foundation
import SpacePushClient
import Testing
import UserNotifications

@MainActor
final class ControlledTransport {
    var requests: [URLRequest] = []
    private var replies: [Int: CheckedContinuation<(Data, URLResponse), any Error>] = [:]
    private var active = 0
    private var closed = false
    private(set) var maximumActive = 0

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard !closed else { throw CancellationError() }
        let index = requests.count
        requests.append(request)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        return try await withCheckedThrowingContinuation { replies[index] = $0 }
    }

    func respond(_ index: Int, body: Data = Data(), status: Int = 204) {
        let response = HTTPURLResponse(url: requests[index].url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        replies.removeValue(forKey: index)?.resume(returning: (body, response))
    }

    func fail(_ index: Int) {
        replies.removeValue(forKey: index)?.resume(throwing: URLError(.timedOut))
    }

    func close() {
        closed = true
        let waiting = replies.values
        replies.removeAll()
        for reply in waiting { reply.resume(throwing: CancellationError()) }
    }
}

@MainActor
final class ControlledRetry {
    private var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var closed = false
    var count: Int { waiting.count }

    func sleep() async throws {
        guard !closed else { throw CancellationError() }
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { reply.resume(throwing: CancellationError()) }
                else { waiting[id] = reply }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiting.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func fire() {
        let replies = waiting.values
        waiting.removeAll()
        for reply in replies { reply.resume() }
    }

    func close() {
        closed = true
        let replies = waiting.values
        waiting.removeAll()
        for reply in replies { reply.resume(throwing: CancellationError()) }
    }
}

@MainActor
final class ControlledNotifications {
    var authorization: UNAuthorizationStatus = .authorized
    var holdQueries = false
    var holdPrompt = false
    private(set) var tokenRequests = 0
    private(set) var promptRequests = 0
    private(set) var queryCount = 0
    private var queries: [Int: CheckedContinuation<UNAuthorizationStatus, Never>] = [:]
    private var prompt: CheckedContinuation<Bool, any Error>?

    func settings() async -> UNAuthorizationStatus {
        let index = queryCount
        queryCount += 1
        if holdQueries { return await withCheckedContinuation { queries[index] = $0 } }
        return authorization
    }

    func request() async throws -> Bool {
        promptRequests += 1
        if holdPrompt { return try await withCheckedThrowingContinuation { prompt = $0 } }
        return true
    }

    func requestToken() { tokenRequests += 1 }
    func answerQuery(_ index: Int, _ status: UNAuthorizationStatus) { queries.removeValue(forKey: index)?.resume(returning: status) }
    func answerPrompt(_ granted: Bool) { let reply = prompt; prompt = nil; reply?.resume(returning: granted) }

    func close() {
        holdQueries = false
        let replies = queries.values
        queries.removeAll()
        for reply in replies { reply.resume(returning: .denied) }
        let reply = prompt
        prompt = nil
        reply?.resume(throwing: CancellationError())
    }
}

enum HarnessError: Error { case timeout }

@MainActor
func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw HarnessError.timeout }
        await Task.yield()
    }
}

@MainActor
final class PushFixture {
    let suite = "net.grafixmafia.SpaceState.PushTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let transport = ControlledTransport()
    let notifications = ControlledNotifications()
    let retry = ControlledRetry()
    let token = Data(repeating: 0xab, count: 32)
    let a = PushSubscription(endpoint: URL(string: "https://a.invalid/status")!)
    let b = PushSubscription(endpoint: URL(string: "https://b.invalid/status")!)
    let c = PushSubscription(endpoint: URL(string: "https://c.invalid/status")!)
    var store: PushStore!

    init() {
        defaults = UserDefaults(suiteName: suite)!
        store = makeStore()
    }

    func makeStore() -> PushStore {
        let transport = transport
        let notifications = notifications
        let retry = retry
        let client = SpacePushClient(baseURL: URL(string: "https://push.invalid")!, load: { try await transport.load($0) })
        return PushStore(client: client, defaults: defaults, system: .init(
            authorization: { await notifications.settings() },
            requestAuthorization: { try await notifications.request() },
            requestToken: { notifications.requestToken() },
            waitForRetry: { try await retry.sleep() }
        ))
    }

    func begin() async throws {
        store.update(subscriptions: [a])
        await store.setEnabled(true)
        store.didRegister(deviceToken: token)
        try await eventually { self.transport.requests.count == 1 }
    }

    func registered() async throws {
        try await begin()
        transport.respond(0)
        try await eventually { self.store.status == .registered }
    }

    func close() {
        notifications.close()
        transport.close()
        retry.close()
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite(.serialized)
@MainActor
struct PushStoreTests {
    @Test func disablingWaitsForInflightPutAndDeletesAfterIt() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.begin()
        await f.store.setEnabled(false)
        #expect(f.transport.requests.count == 1)
        #expect(f.store.status == .off)
        f.transport.respond(0)
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpMethod == "DELETE")
        #expect(f.store.status != .registered)
        f.transport.respond(1)
        try await eventually { f.store.status == .off }
        #expect(f.transport.maximumActive == 1)
    }

    @Test func spaceChangesCoalesceToTheLatestSubscription() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.begin()
        f.store.update(subscriptions: [f.b])
        f.store.update(subscriptions: [f.c])
        #expect(f.transport.requests.count == 1)
        f.transport.respond(0)
        try await eventually { f.transport.requests.count == 2 }
        let body = String(data: try #require(f.transport.requests[1].httpBody), encoding: .utf8)!
        #expect(body.contains(f.c.endpoint.absoluteString))
        #expect(!body.contains(f.b.endpoint.absoluteString))
        f.transport.respond(1)
        try await eventually { f.store.status == .registered }
        #expect(f.transport.maximumActive == 1)
    }

    @Test func reenablingWaitsForDeleteBeforeRegisteringAgain() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.registered()
        await f.store.setEnabled(false)
        try await eventually { f.transport.requests.count == 2 }
        await f.store.setEnabled(true)
        #expect(f.transport.requests.count == 2)
        f.transport.respond(1)
        try await eventually { f.transport.requests.count == 3 }
        #expect(f.transport.requests.map(\.httpMethod) == ["PUT", "DELETE", "PUT"])
        f.transport.respond(2)
        try await eventually { f.store.status == .registered }
        #expect(f.transport.maximumActive == 1)
    }

    @Test func failedDeleteIsVisibleAndSurvivesRestartWhileOff() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.registered()
        await f.store.setEnabled(false)
        try await eventually { f.transport.requests.count == 2 }
        f.transport.fail(1)
        try await eventually { if case .failed = f.store.status { return f.retry.count == 1 }; return false }
        #expect(!f.store.isEnabled)
        let restarted = f.makeStore()
        restarted.start()
        try await eventually { f.transport.requests.count == 3 }
        #expect(f.transport.requests[2].httpMethod == "DELETE")
        #expect(f.transport.requests[2].url?.lastPathComponent == SpacePushClient.hex(f.token))
        f.transport.respond(2)
        try await eventually { restarted.status == .off }
    }

    @Test func failedUnchangedPutRetriesAutomatically() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.begin()
        f.transport.respond(0, status: 503)
        try await eventually { f.retry.count == 1 }
        if case .failed = f.store.status {} else { Issue.record("failure must be visible") }
        f.retry.fire()
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpBody == f.transport.requests[0].httpBody)
        f.transport.respond(1)
        try await eventually { f.store.status == .registered }
    }

    @Test func disablingCancelsAStaleRetryAndCleansUncertainPut() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.begin()
        f.transport.fail(0)
        try await eventually { f.retry.count == 1 }
        await f.store.setEnabled(false)
        f.retry.fire()
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpMethod == "DELETE")
        f.transport.respond(1)
        for _ in 0..<20 { await Task.yield() }
        #expect(f.transport.requests.count == 2)
        #expect(f.store.status == .off)
    }

    @Test func permissionGrantedAfterDisablingDoesNotEnableAgain() async throws {
        let f = PushFixture(); defer { f.close() }
        f.notifications.authorization = .notDetermined
        f.notifications.holdPrompt = true
        let enable = Task { await f.store.setEnabled(true) }
        try await eventually { f.notifications.promptRequests == 1 }
        await f.store.setEnabled(false)
        f.notifications.answerPrompt(true)
        await enable.value
        #expect(!f.store.isEnabled)
        #expect(f.store.status == .off)
        #expect(f.notifications.tokenRequests == 0)
        #expect(f.transport.requests.isEmpty)
    }

    @Test func lateTokenAndFailureAfterDisablingNeverRegister() async throws {
        let f = PushFixture(); defer { f.close() }
        f.store.didRegister(deviceToken: f.token)
        f.store.didFailToRegister(URLError(.notConnectedToInternet))
        try await eventually { f.transport.requests.count == 1 }
        #expect(f.transport.requests[0].httpMethod == "DELETE")
        f.transport.respond(0)
        try await eventually { f.store.status == .off }
        #expect(!f.store.isEnabled)
    }

    @Test func foregroundRechecksRevokedAndRestoredPermissionWithoutPrompt() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.registered()
        f.notifications.authorization = .denied
        await f.store.refreshAuthorization()
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpMethod == "DELETE")
        f.transport.respond(1)
        try await eventually { f.store.status == .denied }
        f.notifications.authorization = .authorized
        await f.store.refreshAuthorization()
        try await eventually { f.transport.requests.count == 3 }
        #expect(f.notifications.tokenRequests == 2)
        #expect(f.notifications.promptRequests == 0)
        f.transport.respond(2)
        try await eventually { f.store.status == .registered }
    }

    @Test func anOldPermissionReadCannotOverrideTheLatestRead() async throws {
        let f = PushFixture(); defer { f.close() }
        f.notifications.holdQueries = true
        let first = Task { await f.store.setEnabled(true) }
        try await eventually { f.notifications.queryCount == 1 }
        await f.store.setEnabled(false)
        let second = Task { await f.store.setEnabled(true) }
        try await eventually { f.notifications.queryCount == 2 }
        f.notifications.answerQuery(1, .denied)
        await second.value
        f.notifications.answerQuery(0, .authorized)
        await first.value
        #expect(f.store.status == .denied)
        #expect(f.notifications.tokenRequests == 0)
        #expect(f.transport.requests.isEmpty)
    }

    @Test func tokenRotationDeletesTheOldTokenBeforeRegisteringTheNewToken() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.begin()
        let replacement = Data(repeating: 0xcd, count: 32)
        f.store.didRegister(deviceToken: replacement)
        f.transport.respond(0)
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpMethod == "DELETE")
        #expect(f.transport.requests[1].url?.lastPathComponent == SpacePushClient.hex(f.token))
        f.transport.respond(1)
        try await eventually { f.transport.requests.count == 3 }
        #expect(f.transport.requests[2].httpMethod == "PUT")
        #expect(f.transport.requests[2].url?.lastPathComponent == SpacePushClient.hex(replacement))
        f.transport.respond(2)
        try await eventually { f.store.status == .registered }
        #expect(f.transport.maximumActive == 1)
    }

    @Test func emptySubscriptionsDeleteAndDoNotClaimRegistration() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.registered()
        f.store.update(subscriptions: [])
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpMethod == "DELETE")
        f.transport.respond(1)
        try await eventually { f.store.status == .off }
        #expect(f.store.isEnabled)
    }

    @Test func coldStartNeedsAFreshTokenAndRenewsTheRegistration() async throws {
        let f = PushFixture(); defer { f.close() }
        try await f.registered()
        let restarted = f.makeStore()
        restarted.update(subscriptions: [f.a])
        await restarted.refreshAuthorization()
        #expect(f.transport.requests.count == 1)
        restarted.didRegister(deviceToken: f.token)
        try await eventually { f.transport.requests.count == 2 }
        #expect(f.transport.requests[1].httpMethod == "PUT")
        f.transport.respond(1)
        try await eventually { restarted.status == .registered }
    }
}
