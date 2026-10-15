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
                .widgetURL(entry.widgetURL)
                .containerBackground(for: .widget) { SpaceWidgetBackground() }
        }
        .configurationDisplayName("Space Status")
        .description("Shows whether a hackerspace is open.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}
