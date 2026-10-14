import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import Testing

@Suite(.serialized)
@MainActor
struct SpaceNavigationTests {
    private let primary = URL(string: "https://a.invalid/api")!

    @Test func linkRoundTripPreservesTheCompleteEndpoint() throws {
        let raw = "https://space.invalid:8443/api?room=one&next=https%3A%2F%2Fother.invalid%2F%3Fa%3D1%26b%3D2#section"
        let target = try #require(SpaceDestination(endpoint: raw))
        let decoded = try #require(SpaceDestination(url: target.url))
        #expect(decoded == target)
        #expect(decoded.endpoint.absoluteString == raw)
    }

    @Test func invalidEndpointFormsAreRejectedBeforeNavigation() {
        for raw in ["", "/api", "file:///tmp/status", "javascript:alert(1)", "https://u:p@space.invalid/api",
                    "https://space.invalid:0/api", "https://space.invalid:65536/api", "https://space.invalid:/api",
                    "https://space.invalid/api\n", "https://space.invalid/api?x=%0a", "https://space.invalid/%7f"] {
            #expect(SpaceDestination(endpoint: raw) == nil, "Invalid endpoint accepted")
        }
    }

    @Test func theEndpointContractStillAllowsLocalHTTPAndPorts() {
        #expect(SpaceDestination(endpoint: "http://localhost:8080/api?space=one") != nil)
        #expect(SpaceDestination(endpoint: "http://[::1]:8080/api") != nil)
    }

    @Test func unexpectedLinkRoutesOrAmbiguousQueriesAreRejected() {
        let query = "endpoint=https%3A%2F%2Fa.invalid%2Fapi"
        for raw in ["https://status?\(query)", "spacestate://other?\(query)", "spacestate://status/path?\(query)",
                    "spacestate://status:?\(query)", "spacestate://status:999999999999999999999?\(query)",
                    "spacestate://user@status?\(query)", "spacestate://status?\(query)#fragment",
                    "spacestate://status?\(query)&\(query)", "spacestate://status?\(query)&state=open",
                    "spacestate://status?\(query)&room=space&room=space", "spacestate://status?room=space",
                    "spacestate://status?\(query)&room", "spacestate://status?endpoint="] {
            #expect(URL(string: raw).flatMap { SpaceDestination(url: $0) } == nil, "Invalid link accepted")
        }
    }

    @Test func roomFocusIsBoundedAndOnlyAppliesToMainframe() throws {
        let target = try #require(SpaceDestination(endpoint: Mainframe.spaceAPIEndpoint.absoluteString, room: "lab3d"))
        #expect(SpaceDestination(url: target.url) == target)
        #expect(SpaceDestination(endpoint: primary.absoluteString, room: "lab3d") == nil)
        for room in ["", "Lab3D", "room/name", "../room", "a b", String(repeating: "a", count: 33)] {
            #expect(SpaceDestination(endpoint: Mainframe.spaceAPIEndpoint.absoluteString, room: room) == nil)
        }
        #expect(SpaceDestination(endpoint: Mainframe.spaceAPIEndpoint.absoluteString, room: "future_room") != nil)
    }

    @Test func genericSpacePayloadAndLegacyNotificationsHaveSafeFallbacks() {
        #expect(SpaceDestination.notification(endpoint: primary.absoluteString, room: "space", fallback: Mainframe.spaceAPIEndpoint)?.room == nil)
        #expect(SpaceDestination.notification(endpoint: nil, room: nil, fallback: primary)?.endpoint == primary)
        #expect(SpaceDestination.notification(endpoint: nil, room: "lab3d", fallback: Mainframe.spaceAPIEndpoint) == nil)
        #expect(SpaceDestination.notification(endpoint: "broken", room: nil, fallback: primary) == nil)
    }

    @Test func oversizedIdentitiesAreRejected() {
        #expect(SpaceDestination(endpoint: "https://space.invalid/" + String(repeating: "a", count: 8192)) == nil)
        let url = URL(string: "spacestate://status?endpoint=https://space.invalid/" + String(repeating: "a", count: 32768))!
        #expect(SpaceDestination(url: url) == nil)
    }

    @Test func failedWidgetReadsStillOpenTheConfiguredSpace() throws {
        let snapshot = WidgetSnapshot(fallbackName: "Last name", space: nil, rooms: nil, expectsRooms: false, endpoint: primary)
        let entry = snapshot.entry(at: .now)
        #expect(entry.status == .unknown)
        let url = try #require(entry.widgetURL)
        #expect(SpaceDestination(url: url)?.endpoint == primary)
        #expect(SpaceEntry.placeholder.widgetURL == nil)
    }

    @Test func widgetExpiryDoesNotChangeItsDestination() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Data(#"{"space":"A","url":"https://different.invalid/","state":{"open":true}}"#.utf8))
        let timing = ObservationTiming(source: .direct, observedAt: now, receivedAt: now, maximumAge: 60)
        let snapshot = WidgetSnapshot(fallbackName: "A", space: StatusObservation(value: info, timing: timing),
            rooms: nil, expectsRooms: false, endpoint: primary)
        let entries = snapshot.entries(from: now)
        #expect(entries.map(\.status) == [.open, .unknown])
        #expect(entries.allSatisfy { $0.widgetURL.flatMap { SpaceDestination(url: $0) }?.endpoint == primary })
    }

    @Test func temporarySelectionDoesNotChangeSavedPreferences() {
        let f = StatusFixture(); defer { f.close() }
        f.defaults.set(300, forKey: "refreshSeconds")
        f.defaults.set(["woodworking"], forKey: "mainframePushRoomIDs")
        let temporary = StatusStore(defaults: f.defaults, selection: .temporary(f.b))
        defer { temporary.pausePolling() }
        #expect(temporary.endpoint == f.b)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == f.a.absoluteString)
        temporary.endpoint = Mainframe.spaceAPIEndpoint
        temporary.refreshInterval = .seconds(900)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == f.a.absoluteString)
        #expect(f.defaults.integer(forKey: "refreshSeconds") == 300)
        #expect(f.defaults.stringArray(forKey: "mainframePushRoomIDs") == ["woodworking"])
        #expect(f.store.endpoint == f.a)
    }

    @Test func temporaryRoomReadsCannotChangeSubscriptionsOrReloadWidgets() async {
        let f = ObservationFixture(proxy: false); defer { f.close() }
        f.defaults.set(["woodworking"], forKey: "mainframePushRoomIDs")
        var reloads = 0
        let store = temporaryStore(f, endpoint: Mainframe.spaceAPIEndpoint, reload: { reloads += 1 })
        defer { store.pausePolling() }
        await store.refresh()
        #expect(store.rooms.map(\.id) == ["lab3d"])
        #expect(f.defaults.stringArray(forKey: "mainframePushRoomIDs") == ["woodworking"])
        #expect(store.pushSubscriptions.count == 1)
        #expect(reloads == 0)
    }

    @Test func temporaryViewUsesOriginalFreshnessRatherThanPayloadState() async {
        let f = ObservationFixture(); defer { f.close() }
        let store = temporaryStore(f, endpoint: Mainframe.spaceAPIEndpoint)
        defer { store.pausePolling() }
        #expect(store.status == .unknown)
        await store.refresh()
        #expect(store.status == .open)
        #expect(store.observationTiming?.observedAt == Date(timeIntervalSince1970: 900))
        f.responses.clock.date = Date(timeIntervalSince1970: 1200)
        #expect(store.status == .unknown)
        #expect(store.info?.status == .open)
    }

    @Test func navigationDoesNotPersistTheOpenedEndpoint() throws {
        let f = ObservationFixture(); defer { f.close() }
        f.defaults.set(primary.absoluteString, forKey: "spaceEndpoint")
        let navigation = SpaceNavigation { self.temporaryStore(f, endpoint: $0) }
        defer { navigation.close() }
        let target = try #require(SpaceDestination(endpoint: "https://other.invalid/api"))
        navigation.open(target)
        #expect(navigation.destination?.target == target)
        #expect(navigation.destination?.store.endpoint == target.endpoint)
        #expect(navigation.destination?.store.info == nil)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == primary.absoluteString)
        navigation.close()
        #expect(navigation.destination == nil)
        #expect(f.defaults.string(forKey: "spaceEndpoint") == primary.absoluteString)
    }

    @Test func invalidLinksLeaveAnExistingDestinationUntouched() throws {
        let f = ObservationFixture(); defer { f.close() }
        var made = 0
        let navigation = SpaceNavigation { made += 1; return self.temporaryStore(f, endpoint: $0) }
        defer { navigation.close() }
        navigation.open(try #require(SpaceDestination(endpoint: primary.absoluteString)))
        let id = navigation.destination?.id
        #expect(!navigation.open(url: URL(string: "spacestate://status?endpoint=file:///tmp/x")!))
        #expect(navigation.destination?.id == id)
        #expect(made == 1)
    }

    @Test func replacingTheTargetCancelsAnOldPendingRead() async throws {
        let f = StatusFixture(); defer { f.close() }
        let transport = f.transport
        let service = StatusService(spacePush: nil, direct: StatusClient(load: { try await transport.load($0) }))
        let navigation = SpaceNavigation { StatusStore(service: service, defaults: f.defaults, selection: .temporary($0)) }
        defer { navigation.close() }
        navigation.open(try #require(SpaceDestination(endpoint: f.a.absoluteString)))
        let old = try #require(navigation.destination?.store)
        let reading = Task { await old.refresh() }
        try await f.waitForRequests(1)
        navigation.open(try #require(SpaceDestination(endpoint: f.b.absoluteString)))
        #expect(!old.isRefreshing)
        f.respond(0, open: true)
        await reading.value
        #expect(old.info == nil)
        #expect(navigation.destination?.store.endpoint == f.b)
        #expect(navigation.destination?.store.info == nil)
    }

    @Test func closingTheTargetCancelsItsPendingRead() async throws {
        let f = StatusFixture(); defer { f.close() }
        let transport = f.transport
        let service = StatusService(spacePush: nil, direct: StatusClient(load: { try await transport.load($0) }))
        let navigation = SpaceNavigation { StatusStore(service: service, defaults: f.defaults, selection: .temporary($0)) }
        navigation.open(try #require(SpaceDestination(endpoint: f.b.absoluteString)))
        let store = try #require(navigation.destination?.store)
        let reading = Task { await store.refresh() }
        try await f.waitForRequests(1)
        navigation.close()
        #expect(!store.isRefreshing)
        f.respond(0, open: true)
        await reading.value
        #expect(store.info == nil)
        #expect(navigation.destination == nil)
        #expect(f.store.endpoint == f.a)
    }

    private func temporaryStore(_ f: ObservationFixture, endpoint: URL, reload: @escaping () -> Void = {}) -> StatusStore {
        let clock = f.responses.clock
        return StatusStore(service: f.responses.service(proxy: true), defaults: f.defaults, reloadWidgets: reload,
            waitForExpiry: { _ in try await f.expiry.sleep() }, now: { clock.date }, selection: .temporary(endpoint))
    }
}
