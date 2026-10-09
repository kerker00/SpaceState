import MainframeStatus
import SpaceAPI
import SwiftUI
import WidgetKit

@main
struct SpaceStateWidgets: WidgetBundle {
    var body: some Widget {
        SpaceStatusWidget()
    }
}

struct SpaceStatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SpaceStatus", intent: SelectSpaceIntent.self, provider: Provider()) { entry in
            SpaceStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Space Status")
        .description("Shows whether a hackerspace is open.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct SpaceStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpaceEntry

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.status.symbolName)
                    .font(.title2)
            }
            .widgetAccentable()
        case .accessoryInline:
            Label(entry.name, systemImage: entry.status.symbolName)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.name)
                    .font(.headline)
                    .widgetAccentable()
                Label {
                    Text(entry.status.title)
                } icon: {
                    Image(systemName: entry.status.symbolName)
                }
                if let since = entry.since {
                    Text(since, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        #endif
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                summary
                if !entry.rooms.isEmpty {
                    Divider()
                    rooms
                }
            }
        default:
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.status.symbolName)
                .font(.title)
                .foregroundStyle(entry.status.color)
            Spacer(minLength: 0)
            Text(entry.name)
                .font(.headline)
                .lineLimit(2)
            Text(entry.status.title)
                .font(.subheadline.bold())
                .foregroundStyle(entry.status.color)
            if let since = entry.since {
                Text(since, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entry.rooms.prefix(5)) { room in
                HStack(spacing: 6) {
                    StatusDot(color: room.state.color)
                    Text(room.name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(room.state.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
