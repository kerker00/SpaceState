import Foundation
import MainframeStatus
import SpaceAPI
import Testing

@MainActor
struct WidgetObservationTests {
    private let date = Date(timeIntervalSince1970: 1000)

    private func snapshot(spaceTime: TimeInterval = 900, roomTime: TimeInterval = 950) throws -> WidgetSnapshot {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Data(#"{"space":"A","state":{"open":true,"lastchange":1}}"#.utf8))
        let timing: (TimeInterval) -> ObservationTiming = { time in
            ObservationTiming(source: .spacePush, observedAt: Date(timeIntervalSince1970: time),
                receivedAt: date, maximumAge: 200)
        }
        return WidgetSnapshot(fallbackName: "Fallback", space: StatusObservation(value: info, timing: timing(spaceTime)),
            rooms: StatusObservation(value: [MainframeRoom(id: "lab3d", state: .open, since: Date(timeIntervalSince1970: 1))],
                                     timing: timing(roomTime)), expectsRooms: true)
    }

    @Test func timelineExpiresSpaceAndRoomsAtTheirOwnTimes() throws {
        let entries = try snapshot().entries(from: date)
        #expect(entries.map(\.date) == [date, Date(timeIntervalSince1970: 1100), Date(timeIntervalSince1970: 1150)])
        #expect(entries.map(\.status) == [.open, .unknown, .unknown])
        #expect(entries[1].rooms[0].state == .open)
        #expect(entries[2].rooms[0].state.status == .unknown)
        #expect(entries[0].since == Date(timeIntervalSince1970: 1))
        #expect(entries[1].since == nil)
        #expect(entries[1].observedAt == Date(timeIntervalSince1970: 900))
    }

    @Test func roomExpiryDoesNotPrematurelyExpireSpace() throws {
        let entries = try snapshot(spaceTime: 950, roomTime: 900).entries(from: date)
        #expect(entries[1].status == .open)
        #expect(entries[1].rooms[0].state.status == .unknown)
        #expect(entries[1].roomsUnavailable)
    }

    @Test func equalExpiriesProduceOneTransition() throws {
        let entries = try snapshot(spaceTime: 900, roomTime: 900).entries(from: date)
        #expect(entries.count == 2)
        #expect(entries[1].status == .unknown)
        #expect(entries[1].rooms[0].state.status == .unknown)
    }

    @Test func alreadyExpiredAndFutureValuesNeverDisplayCurrentOpenings() throws {
        for time: TimeInterval in [99, 1001] {
            let entries = try snapshot(spaceTime: time, roomTime: time).entries(from: date)
            #expect(entries.count == 1)
            #expect(entries[0].status == .unknown)
            #expect(entries[0].rooms[0].state.status == .unknown)
            #expect(entries[0].since == nil)
        }
    }

    @Test func roomFailureDoesNotEraseAValidSpaceObservation() throws {
        let original = try snapshot()
        let snapshot = WidgetSnapshot(fallbackName: "Fallback", space: original.space, rooms: nil, expectsRooms: true)
        let entry = snapshot.entry(at: date)
        #expect(entry.status == .open)
        #expect(entry.rooms.isEmpty)
        #expect(entry.roomsUnavailable)
    }

    @Test func spaceFailureDoesNotEraseValidRoomsOrInventASourceTime() throws {
        let original = try snapshot()
        let snapshot = WidgetSnapshot(fallbackName: "Fallback", space: nil, rooms: original.rooms, expectsRooms: true)
        let entry = snapshot.entry(at: date)
        #expect(entry.name == "Fallback")
        #expect(entry.status == .unknown)
        #expect(entry.rooms[0].state == .open)
        #expect(entry.observedAt == nil)
    }
}
