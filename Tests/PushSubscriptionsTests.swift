import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import Testing

@MainActor
final class RoomResponses {
    var failRooms = false
    var rooms = #"{"lab3d":{"state":"open"},"woodworking":{"state":"closed"}}"#

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        let isRooms = request.url == Mainframe.openStateURL
        if isRooms && failRooms { throw URLError(.timedOut) }
        let body = isRooms ? rooms : #"{"space":"Mainframe","state":{"open":true}}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    var service: StatusService {
        StatusService(spacePush: nil, direct: StatusClient(load: { try await self.load($0) }))
    }
}

@Suite(.serialized)
@MainActor
struct PushSubscriptionsTests {
    @Test func aFailedRoomReadKeepsDesiredSubscriptionsAcrossRestart() async throws {
        let suite = "net.grafixmafia.SpaceState.RoomTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let responses = RoomResponses()
        let store = StatusStore(service: responses.service, defaults: defaults, reloadWidgets: {})
        await store.refresh()
        let wanted = store.pushSubscriptions
        #expect(wanted.count == 3)
        responses.failRooms = true
        await store.refresh()
        #expect(store.rooms.count == 2)
        #expect(store.lastRoomsError != nil)
        #expect(store.displayRooms.allSatisfy { $0.state.status == .unknown })
        #expect(store.pushSubscriptions == wanted)
        let restarted = StatusStore(service: responses.service, defaults: defaults, reloadWidgets: {})
        #expect(restarted.pushSubscriptions == wanted)
    }

    @Test func partialRoomResponsesDoNotRemoveKnownDesiredRooms() async throws {
        let suite = "net.grafixmafia.SpaceState.RoomTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let responses = RoomResponses()
        let store = StatusStore(service: responses.service, defaults: defaults, reloadWidgets: {})
        await store.refresh()
        responses.rooms = #"{"lab3d":{"broken":true},"woodworking":{"state":"open"},"radstelle":{"state":"open"}}"#
        await store.refresh()
        #expect(Set(store.pushSubscriptions.compactMap(\.room)) == Set(["lab3d", "woodworking", "radstelle"]))
    }

    @Test func switchingSpaceChangesSubscriptionsAndCachedRoomsStayBounded() async throws {
        let suite = "net.grafixmafia.SpaceState.RoomTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set((0..<80).map { "room_\($0)" } + ["space", "UPPER", "bad room"], forKey: "mainframePushRoomIDs")
        let responses = RoomResponses()
        let store = StatusStore(service: responses.service, defaults: defaults, reloadWidgets: {})
        #expect(store.pushSubscriptions.count == 50)
        let other = URL(string: "https://other.invalid/status")!
        store.endpoint = other
        #expect(store.pushSubscriptions == [PushSubscription(endpoint: other)])
    }
}
