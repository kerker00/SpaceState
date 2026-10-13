import Foundation
import SpaceAPI
import SpacePushClient
import Testing

@MainActor
final class StatusFixture {
    let suite = "net.grafixmafia.SpaceState.StatusTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let transport = ControlledTransport()
    let ticker = ControlledRetry()
    let a = URL(string: "https://a.invalid/status")!
    let b = URL(string: "https://b.invalid/status")!
    var date = Date(timeIntervalSince1970: 100)
    var reloads = 0
    var pollDurations: [Duration] = []
    var store: StatusStore!

    init() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(a.absoluteString, forKey: "spaceEndpoint")
        let transport = transport
        let service = StatusService(spacePush: nil, direct: StatusClient(load: { try await transport.load($0) }))
        store = StatusStore(service: service, defaults: defaults,
            reloadWidgets: { [weak self] in self?.reloads += 1 },
            waitForPoll: { [weak self] duration in
                guard let self else { throw CancellationError() }
                self.pollDurations.append(duration)
                try await self.ticker.sleep()
            },
            now: { [weak self] in self?.date ?? .distantPast }
        )
    }

    func respond(_ index: Int, open: Bool) {
        let body = #"{"space":"Test space","state":{"open":\#(open)}}"#
        transport.respond(index, body: Data(body.utf8), status: 200)
    }

    func waitForRequests(_ count: Int) async throws {
        try await eventually { self.transport.requests.count == count }
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func close() {
        store.pausePolling()
        ticker.close()
        transport.close()
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite(.serialized)
@MainActor
struct StatusRefreshTests {
    @Test func overlappingRefreshesDiscardOldResultsAndAwaitTheLatest() async throws {
        let f = StatusFixture(); defer { f.close() }
        let first = Task { await f.store.refresh() }
        try await f.waitForRequests(1)
        let second = Task { await f.store.refresh() }
        let third = Task { await f.store.refresh() }
        await f.settle()
        #expect(f.transport.requests.count == 1)
        f.respond(0, open: true)
        try await f.waitForRequests(2)
        #expect(f.store.info == nil)
        #expect(f.store.isRefreshing)
        #expect(f.reloads == 0)
        f.respond(1, open: false)
        await first.value; await second.value; await third.value
        #expect(f.store.status == .closed)
        #expect(!f.store.isRefreshing)
        #expect(f.transport.requests.count == 2)
        #expect(f.transport.maximumActive == 1)
    }

    @Test func anObsoleteFailureDoesNotPublishAnError() async throws {
        let f = StatusFixture(); defer { f.close() }
        let first = Task { await f.store.refresh() }
        try await f.waitForRequests(1)
        let second = Task { await f.store.refresh() }
        await f.settle()
        f.transport.fail(0)
        try await f.waitForRequests(2)
        #expect(f.store.lastError == nil)
        #expect(f.store.lastUpdate == nil)
        f.respond(1, open: true)
        await first.value; await second.value
        #expect(f.store.status == .open)
        #expect(f.store.lastError == nil)
    }

    @Test func switchingAwayAndBackCannotPublishTheOriginalRequest() async throws {
        let f = StatusFixture(); defer { f.close() }
        let original = Task { await f.store.refresh() }
        try await f.waitForRequests(1)
        f.store.endpoint = f.b
        let other = Task { await f.store.refresh() }
        try await f.waitForRequests(2)
        f.store.endpoint = f.a
        let current = Task { await f.store.refresh() }
        try await f.waitForRequests(3)
        f.respond(0, open: false)
        f.transport.fail(1)
        await original.value; await other.value
        #expect(f.store.info == nil)
        #expect(f.store.lastError == nil)
        #expect(f.store.isRefreshing)
        f.respond(2, open: true)
        await current.value
        #expect(f.store.endpoint == f.a)
        #expect(f.store.status == .open)
        #expect(f.reloads == 1)
    }

    @Test func anOldWorkerCannotClearTheNewRefreshIndicator() async throws {
        let f = StatusFixture(); defer { f.close() }
        let original = Task { await f.store.refresh() }
        try await f.waitForRequests(1)
        f.store.endpoint = f.b
        let current = Task { await f.store.refresh() }
        try await f.waitForRequests(2)
        f.respond(0, open: true)
        await original.value
        #expect(f.store.isRefreshing)
        #expect(f.store.lastUpdate == nil)
        f.respond(1, open: false)
        await current.value
        #expect(!f.store.isRefreshing)
        #expect(f.store.status == .closed)
    }

    @Test func successAndAttemptTimesStayDistinctAndRecoveryReloadsWidgets() async throws {
        let f = StatusFixture(); defer { f.close() }
        let first = Task { await f.store.refresh() }
        try await f.waitForRequests(1)
        f.respond(0, open: true)
        await first.value
        #expect(f.store.lastUpdate == Date(timeIntervalSince1970: 100))
        f.date = Date(timeIntervalSince1970: 200)
        let failure = Task { await f.store.refresh() }
        try await f.waitForRequests(2)
        f.transport.fail(1)
        await failure.value
        #expect(f.store.lastAttempt == f.date)
        #expect(f.store.lastUpdate == Date(timeIntervalSince1970: 100))
        #expect(f.store.lastError != nil)
        #expect(f.store.status == .unknown)
        #expect(f.reloads == 2)
        f.date = Date(timeIntervalSince1970: 300)
        let recovery = Task { await f.store.refresh() }
        try await f.waitForRequests(3)
        f.respond(2, open: true)
        await recovery.value
        #expect(f.store.lastUpdate == f.date)
        #expect(f.store.status == .open)
        #expect(f.reloads == 3)
    }

    @Test func pausingDropsAnInFlightResultAndStopsPolling() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.startPolling()
        try await f.waitForRequests(1)
        f.store.pausePolling()
        #expect(!f.store.isRefreshing)
        f.respond(0, open: true)
        await f.settle()
        #expect(f.store.info == nil)
        #expect(f.store.lastUpdate == nil)
        #expect(f.reloads == 0)
        #expect(f.ticker.count == 0)
        #expect(f.transport.requests.count == 1)
    }

    @Test func resumingStartsOnePollAndResumesAfterBackgroundPause() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.resumePolling()
        f.store.resumePolling()
        try await f.waitForRequests(1)
        f.respond(0, open: true)
        try await eventually { f.ticker.count == 1 }
        f.store.resumePolling()
        #expect(f.transport.requests.count == 1)
        f.ticker.fire()
        try await f.waitForRequests(2)
        f.respond(1, open: false)
        try await eventually { f.ticker.count == 1 }
        f.store.pausePolling()
        try await eventually { f.ticker.count == 0 }
        f.ticker.fire()
        await f.settle()
        #expect(f.transport.requests.count == 2)
        f.store.resumePolling()
        try await f.waitForRequests(3)
        f.respond(2, open: false)
        try await eventually { f.ticker.count == 1 }
    }

    @Test func intervalChangesUseTheNewDuration() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.startPolling()
        try await f.waitForRequests(1)
        f.respond(0, open: true)
        try await eventually { f.ticker.count == 1 }
        #expect(f.pollDurations == [.seconds(120)])
        f.store.refreshInterval = .seconds(60)
        try await f.waitForRequests(2)
        f.respond(1, open: true)
        try await eventually { f.pollDurations.count == 2 }
        #expect(f.pollDurations.last == .seconds(60))
    }

    @Test func aCurrentSpaceNotificationQueuesRefreshAndReloadsWidgets() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.notificationReceived(endpoint: f.a.absoluteString)
        #expect(f.reloads == 1)
        #expect(f.store.isRefreshing)
        try await f.waitForRequests(1)
        f.respond(0, open: false)
        try await eventually { !f.store.isRefreshing }
        #expect(f.store.status == .closed)
        #expect(f.store.endpoint == f.a)
        #expect(f.reloads == 2)
    }

    @Test func otherAndMalformedNotificationEndpointsCannotChangeOrFetchTheSelection() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.notificationReceived(endpoint: f.b.absoluteString)
        f.store.notificationReceived(endpoint: "file:///etc/passwd")
        f.store.notificationReceived(endpoint: "not a URL")
        await f.settle()
        #expect(f.reloads == 3)
        #expect(f.transport.requests.isEmpty)
        #expect(f.store.endpoint == f.a)
        // Legacy notifications without an endpoint may refresh only the selection.
        f.store.notificationReceived(endpoint: nil)
        try await f.waitForRequests(1)
        #expect(f.transport.requests[0].url == f.a)
        f.respond(0, open: true)
        try await eventually { !f.store.isRefreshing }
    }

    @Test func manualRefreshAndPollingShareOneWorker() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.startPolling()
        try await f.waitForRequests(1)
        let manual = Task { await f.store.refresh() }
        await f.settle()
        f.respond(0, open: true)
        try await f.waitForRequests(2)
        f.respond(1, open: false)
        await manual.value
        try await eventually { f.ticker.count == 1 }
        #expect(f.store.status == .closed)
        #expect(f.transport.maximumActive == 1)
    }

    @Test func selectionAndIntervalChangesDoNotRestartPausedPolling() async throws {
        let f = StatusFixture(); defer { f.close() }
        f.store.pausePolling()
        f.store.endpoint = f.b
        f.store.refreshInterval = .seconds(60)
        await f.settle()
        #expect(f.transport.requests.isEmpty)
        f.store.resumePolling()
        try await f.waitForRequests(1)
        #expect(f.transport.requests[0].url == f.b)
        f.respond(0, open: true)
        try await eventually { f.ticker.count == 1 }
        #expect(f.pollDurations == [.seconds(60)])
    }
}
