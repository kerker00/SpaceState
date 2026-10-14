import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import WidgetKit

/// Fetches the configured space through SpacePush (or directly as fallback).
/// WidgetKit allows only a few refreshes per hour, so a new entry is requested
/// every 15 minutes; the apps also reload widgets when a notification arrives.
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpaceEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectSpaceIntent, in context: Context) async -> SpaceEntry {
        context.isPreview ? .placeholder : await snapshot(for: configuration).entry(at: .now)
    }

    func timeline(for configuration: SelectSpaceIntent, in context: Context) async -> Timeline<SpaceEntry> {
        let snapshot = await snapshot(for: configuration)
        let date = Date()
        return Timeline(entries: snapshot.entries(from: date), policy: .after(date.addingTimeInterval(15 * 60)))
    }

    private func snapshot(for configuration: SelectSpaceIntent) async -> WidgetSnapshot {
        let space = configuration.space ?? .mainframe
        guard let endpoint = SpaceDestination(endpoint: space.id)?.endpoint else {
            return WidgetSnapshot(fallbackName: space.name, space: nil, rooms: nil, expectsRooms: false)
        }
        let service = StatusService.configured
        async let info = try? service.spaceObservation(at: endpoint)
        let expectsRooms = Mainframe.isMainframe(endpoint)
        let rooms: StatusObservation<[MainframeRoom]>?
        if expectsRooms { rooms = try? await service.mainframeRoomsObservation() }
        else { rooms = nil }
        return WidgetSnapshot(fallbackName: space.name, space: await info, rooms: rooms,
            expectsRooms: expectsRooms, endpoint: endpoint)
    }
}
