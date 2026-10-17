import Foundation
import MainframeStatus
import SpaceAPI
import WidgetKit

struct SpaceEntry: TimelineEntry {
    let date: Date
    let name: String
    let status: SpaceStatus
    let since: Date?
    let rooms: [MainframeRoom]
    let observedAt: Date?
    let roomsUnavailable: Bool
    var endpoint: URL? = nil
    var sensors: [WidgetSensorReading] = []

    var widgetURL: URL? { endpoint.flatMap { SpaceDestination(endpoint: $0.absoluteString)?.url } }

    static let placeholder = SpaceEntry(date: .now, name: "Mainframe", status: .open,
        since: .now.addingTimeInterval(-3600), rooms: [
            MainframeRoom(id: "space", state: .open, since: nil),
            MainframeRoom(id: "radstelle", state: .member, since: nil),
            MainframeRoom(id: "lab3d", state: .closed, since: nil),
            MainframeRoom(id: "machining", state: .closed, since: nil),
        ], observedAt: .now, roomsUnavailable: false)
}

/// Every expiry is an explicit unknown timeline entry, without requiring another
/// network fetch. WidgetKit remains responsible for scheduling and rendering it.
struct WidgetSnapshot {
    let fallbackName: String
    let space: StatusObservation<SpaceInfo>?
    let rooms: StatusObservation<[MainframeRoom]>?
    let expectsRooms: Bool
    var endpoint: URL? = nil

    func entry(at date: Date) -> SpaceEntry {
        let status = space.map { $0.timing.currentStatus($0.value.status, at: date) } ?? .unknown
        return SpaceEntry(date: date, name: space?.value.name ?? fallbackName, status: status,
            since: status == .unknown ? nil : space?.value.state?.lastChange,
            rooms: ObservationDisplay.rooms(rooms?.value ?? [], timing: rooms?.timing, at: date),
            observedAt: space?.timing.observedAt,
            roomsUnavailable: expectsRooms && rooms?.timing.freshness(at: date) != .current,
            endpoint: endpoint,
            sensors: SpaceSensorPresentation.widget(info: space?.value, timing: space?.timing, at: date))
    }

    func entries(from date: Date) -> [SpaceEntry] {
        let expiries = Set([space?.timing.expiresAt, rooms?.timing.expiresAt].compactMap { $0 }.filter { $0 > date })
        return ([date] + expiries.sorted()).map { entry(at: $0) }
    }
}
