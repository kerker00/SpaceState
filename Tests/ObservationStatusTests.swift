import Foundation
import MainframeStatus
import Observation
import SpaceAPI
import SpacePushClient
import Synchronization
import Testing

@MainActor
final class ObservationResponses {
    let clock = ObservationTestClock(Date(timeIntervalSince1970: 1000))
    var failSpace = false
    var failRooms = false
    var failDirectory = false
    var cancelDirectory = false
    var spaceFetched = 900
    var roomsFetched = 950
    var requests: [URL] = []
    var directoryBody = #"[{"url":"https://a.invalid/api","lastSeen":990,"data":{"space":"A","state":{"open":true}}},{"url":"https://b.invalid/api","lastSeen":99,"data":{"space":"B","state":{"open":true}}},{"url":"https://c.invalid/api","data":{"space":"C","state":{"open":false}}}]"#

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = request.url!
        requests.append(url)
        let rooms = url.path.hasSuffix("rooms") || url == Mainframe.openStateURL
        let directory = url == SpaceDirectory.aggregatorURL || url.path.hasSuffix("directory")
        if directory && cancelDirectory { throw CancellationError() }
        if (rooms && failRooms) || (directory && failDirectory) || (!rooms && !directory && failSpace) {
            throw URLError(.timedOut)
        }
        let body = directory ? directoryBody : rooms ? #"{"lab3d":{"state":"open","timestamp":1}}"#
            : #"{"space":"Mainframe","state":{"open":true,"lastchange":1}}"#
        let fetched = rooms ? roomsFetched : spaceFetched
        let headers = ["X-SpacePush-Fetched-At": String(fetched), "X-SpacePush-Max-Data-Age": "200",
                       "X-SpacePush-Expires-At": String(fetched + 200)]
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
    }

    func service(proxy: Bool) -> StatusService {
        let clock = clock
        let direct = StatusClient(now: { clock.date }, load: { try await self.load($0) })
        let push = proxy ? SpacePushClient(baseURL: URL(string: "https://push.invalid")!, now: { clock.date },
            load: { try await self.load($0) }) : nil
        return StatusService(spacePush: push, direct: direct)
    }
}

@MainActor
final class ObservationFixture {
    let suite = "net.grafixmafia.SpaceState.ObservationTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let responses = ObservationResponses()
    let expiry = ControlledRetry()
    var expiryDurations: [Duration] = []
    var reloads = 0
    var store: StatusStore!

    init(proxy: Bool = true) {
        defaults = UserDefaults(suiteName: suite)!
        let clock = responses.clock
        store = StatusStore(service: responses.service(proxy: proxy), defaults: defaults,
            reloadWidgets: { [weak self] in self?.reloads += 1 },
            waitForExpiry: { [weak self] duration in
                guard let self else { throw CancellationError() }
                self.expiryDurations.append(duration)
                try await self.expiry.sleep()
            }, now: { clock.date })
    }

    func close() {
        store.pausePolling()
        expiry.close()
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite(.serialized)
@MainActor
struct ObservationStatusTests {
    @Test func proxyObservationAndClientTimesStayDistinct() async {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        #expect(f.store.status == .open)
        #expect(f.store.observationTiming?.observedAt == Date(timeIntervalSince1970: 900))
        #expect(f.store.lastUpdate == Date(timeIntervalSince1970: 1000))
        #expect(f.store.lastAttempt == f.store.lastUpdate)
        #expect(f.store.info?.state?.lastChange == Date(timeIntervalSince1970: 1))
        #expect(f.store.roomsTiming?.observedAt == Date(timeIntervalSince1970: 950))
    }

    @Test func retainedOpeningExpiresBeforeTheNextPoll() async throws {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        try await eventually { f.expiry.count == 1 }
        #expect(f.expiryDurations == [.seconds(100)])
        let requests = f.responses.requests.count
        let previousReloads = f.reloads
        f.responses.clock.date = Date(timeIntervalSince1970: 1100)
        f.expiry.fire()
        try await eventually { f.reloads > previousReloads }
        #expect(f.store.status == .unknown)
        #expect(f.store.freshness == .stale)
        #expect(f.store.info?.status == .open)
        #expect(f.store.displayRooms.first?.state == .open)
        #expect(f.responses.requests.count == requests)
    }

    @Test func roomObservationExpiresIndependently() async throws {
        let f = ObservationFixture(); defer { f.close() }
        f.responses.spaceFetched = 950
        f.responses.roomsFetched = 900
        await f.store.refresh()
        try await eventually { f.expiry.count == 1 }
        let previousReloads = f.reloads
        f.responses.clock.date = Date(timeIntervalSince1970: 1100)
        f.expiry.fire()
        try await eventually { f.reloads > previousReloads }
        #expect(f.store.roomsFreshness == .stale)
        #expect(f.store.status == .open)
        #expect(f.store.rooms.first?.state == .open)
        #expect(f.store.displayRooms.first?.state.status == .unknown)
    }

    @Test func roomFailurePreservesNamesTimesAndDesiredSubscriptions() async {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        let subscriptions = f.store.pushSubscriptions
        let timing = f.store.roomsTiming
        let successful = f.store.lastRoomsUpdate
        f.responses.clock.date = Date(timeIntervalSince1970: 1050)
        f.responses.failRooms = true
        await f.store.refresh()
        #expect(f.store.status == .open)
        #expect(f.store.rooms.map(\.id) == ["lab3d"])
        #expect(f.store.lastRoomsError != nil)
        #expect(f.store.displayRooms.first?.state.status == .unknown)
        #expect(f.store.roomsTiming == timing)
        #expect(f.store.lastRoomsUpdate == successful)
        #expect(f.store.lastRoomsAttempt == f.responses.clock.date)
        #expect(f.store.pushSubscriptions == subscriptions)
    }

    @Test func successfulRoomsRemainIndependentOfAFailedSpaceRead() async {
        let f = ObservationFixture(); defer { f.close() }
        f.responses.failSpace = true
        await f.store.refresh()
        #expect(f.store.info == nil)
        #expect(f.store.status == .unknown)
        #expect(f.store.lastError != nil)
        #expect(f.store.displayRooms.first?.state == .open)
        #expect(f.store.lastRoomsError == nil)
        #expect(f.store.pushSubscriptions.compactMap(\.room) == ["lab3d"])
    }

    @Test func bothReadFailuresCannotRestampOrColourOldStates() async {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        let observation = f.store.observationTiming
        let roomObservation = f.store.roomsTiming
        let update = f.store.lastUpdate
        let subscriptions = f.store.pushSubscriptions
        f.responses.clock.date = Date(timeIntervalSince1970: 1050)
        f.responses.failSpace = true
        f.responses.failRooms = true
        await f.store.refresh()
        #expect(f.store.observationTiming == observation)
        #expect(f.store.roomsTiming == roomObservation)
        #expect(f.store.lastUpdate == update)
        #expect(f.store.lastAttempt == f.responses.clock.date)
        #expect(f.store.status == .unknown)
        #expect(f.store.displayRooms.first?.state.status == .unknown)
        #expect(f.store.pushSubscriptions == subscriptions)
    }

    @Test func roomRecoveryRestoresCurrentDisplayWithoutChangingDesiredRooms() async {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        let desired = f.store.pushSubscriptions
        f.responses.failRooms = true
        await f.store.refresh()
        f.responses.failRooms = false
        f.responses.roomsFetched = 1000
        f.responses.clock.date = Date(timeIntervalSince1970: 1050)
        await f.store.refresh()
        #expect(f.store.lastRoomsError == nil)
        #expect(f.store.displayRooms.first?.state == .open)
        #expect(f.store.lastRoomsUpdate == f.responses.clock.date)
        #expect(f.store.pushSubscriptions == desired)
    }

    @Test func selectionChangeClearsObservationAndRoomErrorState() async throws {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        f.responses.failRooms = true
        await f.store.refresh()
        f.store.endpoint = URL(string: "https://other.invalid/api")!
        #expect(f.store.observationTiming == nil)
        #expect(f.store.roomsTiming == nil)
        #expect(f.store.lastRoomsError == nil)
        #expect(f.store.lastRoomsUpdate == nil)
        #expect(f.store.lastRoomsAttempt == nil)
        #expect(f.store.rooms.isEmpty)
        #expect(f.store.pushSubscriptions.count == 1)
        try await eventually { f.expiry.count == 0 }
    }

    @Test func backwardsClientClockCannotDisplayACurrentOpening() async {
        let f = ObservationFixture(); defer { f.close() }
        await f.store.refresh()
        f.responses.clock.date = Date(timeIntervalSince1970: 999)
        #expect(f.store.status == .unknown)
        #expect(f.store.displayRooms.first?.state.status == .unknown)
    }

    @Test func cancelledOldExpiryCannotPublishForANewObservation() async throws {
        let clock = ObservationTestClock(Date(timeIntervalSince1970: 1000))
        let wait = ControlledTransport()
        // This transport intentionally ignores cancellation until answered.
        let expiry = ObservationExpiry(now: { clock.date }, wait: { _ in
            _ = try await wait.load(URLRequest(url: URL(string: "https://timer.invalid")!))
        })
        defer { expiry.cancel(); wait.close() }
        var changes = 0
        let timing = ObservationTiming(source: .direct, observedAt: clock.date, receivedAt: clock.date, maximumAge: 100)
        expiry.schedule([timing]) { changes += 1 }
        try await eventually { wait.requests.count == 1 }
        expiry.schedule([timing]) { changes += 1 }
        try await eventually { wait.requests.count == 2 }
        wait.respond(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(changes == 0)
        clock.date = Date(timeIntervalSince1970: 1100)
        wait.respond(1)
        try await eventually { changes == 1 }
    }

    @Test func notificationRefreshCanOverlapDirectoryLoadAndExpiryScheduling() async throws {
        let responses = ObservationResponses()
        let directory = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        let expiry = ObservationExpiry(now: { responses.clock.date }, wait: { _ in
            try await Task.sleep(for: .milliseconds(1))
        })
        defer { expiry.cancel() }

        let timing = ObservationTiming(source: .direct,
                                       observedAt: responses.clock.date,
                                       receivedAt: responses.clock.date,
                                       maximumAge: 100)
        expiry.schedule([timing]) { }

        async let directoryLoad: Void = directory.load()
        let refreshStore = StatusStore(service: responses.service(proxy: false),
                                       waitForExpiry: { _ in
                                           try await Task.sleep(for: .milliseconds(1))
                                       },
                                       now: { responses.clock.date },
                                       selection: .temporary(URL(string: "https://a.invalid/api")!))
        refreshStore.notificationReceived(endpoint: "https://a.invalid/api")
        await directoryLoad
        await refreshStore.refresh()

        #expect(directory.entries.count == 3)
        #expect(refreshStore.endpoint.absoluteString == "https://a.invalid/api")
        #expect(refreshStore.info != nil)
        refreshStore.pausePolling()
    }
}

@Suite(.serialized)
@MainActor
struct DirectoryObservationTests {
    @Test func eachDirectoryEntryKeepsItsOwnFreshness() async {
        let responses = ObservationResponses()
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        #expect(store.entries.map { store.status(for: $0) } == [.open, .unknown, .unknown])
        #expect(store.timing(for: store.entries[2])?.observedAt == nil)
        responses.clock.date = Date(timeIntervalSince1970: 1890)
        #expect(store.status(for: store.entries[0]) == .unknown)
        #expect(store.entries.map(\.info.name) == ["A", "B", "C"])
    }

    @Test func directoryFailurePreservesSearchableNamesWithoutCurrentFlags() async {
        let responses = ObservationResponses()
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        responses.failDirectory = true
        await store.load()
        #expect(store.lastError != nil)
        #expect(store.entries.count == 3)
        // Full-text search also matches the 'a' in the retained endpoint URLs.
        #expect(store.entries(matching: "A").count == 3)
        #expect(store.entries(matching: "https://a.invalid").map(\.info.name) == ["A"])
        #expect(store.entries.allSatisfy { store.status(for: $0) == .unknown })
    }

    @Test func directoryCancellationDoesNotPublishAnError() async {
        let responses = ObservationResponses()
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        responses.cancelDirectory = true
        await store.load()
        #expect(store.lastError == nil)
        #expect(store.status(for: store.entries[0]) == .open)
        #expect(!store.isLoading)
    }

    @Test func directoryExpiryPublishesWithoutAnotherRead() async throws {
        let responses = ObservationResponses()
        let wait = ControlledRetry()
        defer { wait.close() }
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date },
            waitForExpiry: { _ in try await wait.sleep() })
        await store.load()
        try await eventually { wait.count == 1 }
        let changed = Mutex(false)
        withObservationTracking { _ = store.status(for: store.entries[0]) } onChange: {
            changed.withLock { $0 = true }
        }
        let requests = responses.requests.count
        responses.clock.date = Date(timeIntervalSince1970: 1890)
        wait.fire()
        try await eventually { changed.withLock { $0 } }
        #expect(store.status(for: store.entries[0]) == .unknown)
        #expect(responses.requests.count == requests)
    }

    @Test func hiddenHannoverAddressFindsSpaceByCity() async {
        let responses = ObservationResponses()
        responses.directoryBody = Self.searchFixture
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        #expect(store.entries(matching: "Hannover").map(\.info.name) == ["LeineLab"])
        #expect(store.entries(matching: "Oldenburg").map(\.info.name) == ["Mainframe"])
    }

    @Test func searchIncludesNestedPublishedContentAndURLs() async {
        let responses = ObservationResponses()
        responses.directoryBody = Self.searchFixture
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        for query in ["Lasercutter", "Nachbarschaft", "werkstattkontakt", "makers.example", "Dachboden", "21.5"] {
            #expect(store.entries(matching: query).map(\.info.name) == ["LeineLab"])
        }
    }

    @Test func searchCombinesWordsAcrossFieldsAndIgnoresWhitespaceAndCase() async {
        let responses = ObservationResponses()
        responses.directoryBody = Self.searchFixture
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        #expect(store.entries(matching: " \n lEiNe\tHANNOVER \n").map(\.info.name) == ["LeineLab"])
        #expect(store.entries(matching: "Hannover Mainframe").isEmpty)
        #expect(store.entries(matching: " \n\t ").map(\.info.name) == ["LeineLab", "Mainframe"])
    }

    @Test func searchDoesNotIndexModelPropertyNamesOrMissingValues() async {
        let responses = ObservationResponses()
        responses.directoryBody = Self.searchFixture
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        for query in ["location", "Optional", "nil", "triggerPerson"] {
            #expect(store.entries(matching: query).isEmpty)
        }
    }

    @Test func searchRetainsHiddenContentAfterLoadFailureWithoutExtraRequests() async {
        let responses = ObservationResponses()
        responses.directoryBody = Self.searchFixture
        let store = DirectoryStore(service: responses.service(proxy: false), now: { responses.clock.date })
        await store.load()
        responses.failDirectory = true
        await store.load()
        let requests = responses.requests.count
        #expect(store.lastError != nil)
        #expect(store.entries(matching: "Hannover Nachbarschaft").map(\.info.name) == ["LeineLab"])
        #expect(responses.requests.count == requests)
    }

    private static let searchFixture = #"""
    [
      {"url":"https://leinelab.invalid/api","lastSeen":990,"data":{
        "space":"LeineLab","location":{"address":"Beispielstraße 5, 30159 Hannover","hint":"Seiteneingang"},
        "contact":{"email":"werkstattkontakt@example.invalid"},
        "links":[{"name":"Werkstatt","description":"Lasercutter für die Nachbarschaft","url":"https://links.example/werkstatt"}],
        "projects":["https://makers.example/projekt"],
        "sensors":{"temperature":[{"value":21.5,"unit":"°C","location":"Dachboden"}]}
      }},
      {"url":"https://mainframe.invalid/api","data":{"space":"Mainframe","location":{"address":"Oldenburg"}}}
    ]
    """#
}
