import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient
import WidgetKit

struct SpaceEntry: TimelineEntry {
    let date: Date
    let name: String
    let status: SpaceStatus
    let since: Date?
    /// Only filled for Mainframe Oldenburg.
    let rooms: [MainframeRoom]

    static let placeholder = SpaceEntry(
        date: .now,
        name: "Mainframe",
        status: .open,
        since: .now.addingTimeInterval(-3600),
        rooms: [
            MainframeRoom(id: "space", state: .open, since: nil),
            MainframeRoom(id: "radstelle", state: .member, since: nil),
            MainframeRoom(id: "lab3d", state: .closed, since: nil),
            MainframeRoom(id: "machining", state: .closed, since: nil),
        ]
    )
}

/// Fetches the configured space through SpacePush (or directly as fallback).
/// WidgetKit allows only a few refreshes per hour, so a new entry is requested
/// every 15 minutes; the apps also reload widgets when a notification arrives.
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpaceEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectSpaceIntent, in context: Context) async -> SpaceEntry {
        context.isPreview ? .placeholder : await entry(for: configuration)
    }

    func timeline(for configuration: SelectSpaceIntent, in context: Context) async -> Timeline<SpaceEntry> {
        Timeline(entries: [await entry(for: configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectSpaceIntent) async -> SpaceEntry {
        let space = configuration.space ?? .mainframe
        guard let endpoint = URL(string: space.id) else {
            return SpaceEntry(date: .now, name: space.name, status: .unknown, since: nil, rooms: [])
        }
        let service = StatusService.configured
        async let info = try? service.space(at: endpoint)
        let rooms = Mainframe.isMainframe(endpoint) ? (try? await service.mainframeRooms()) ?? [] : []
        guard let info = await info else {
            return SpaceEntry(date: .now, name: space.name, status: .unknown, since: nil, rooms: [])
        }
        return SpaceEntry(date: .now, name: info.name, status: info.status, since: info.state?.lastChange, rooms: rooms)
    }
}
