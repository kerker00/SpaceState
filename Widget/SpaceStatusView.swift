import MainframeStatus
import SpaceAPI
import SwiftUI
import WidgetKit

/// Uses the app's semantic palette in full color and the system's foreground
/// roles in tinted/Lock Screen appearances. Status always has a word and symbol.
struct SpaceStatusView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let entry: SpaceEntry

    var body: some View {
        SpaceWidgetContent(entry: entry, layout: SpaceWidgetLayout(family: family),
            renderingMode: renderingMode, palette: SpacePalette(colorScheme: colorScheme, contrast: contrast))
    }
}

/// Separates the supported WidgetKit family from the layout's presentation inputs.
enum SpaceWidgetLayout {
    case small, medium, circular, inline, rectangular

    init(family: WidgetFamily) {
        switch family {
        #if os(iOS)
        case .accessoryCircular: self = .circular
        case .accessoryInline: self = .inline
        case .accessoryRectangular: self = .rectangular
        #endif
        case .systemMedium: self = .medium
        default: self = .small
        }
    }
}

struct SpaceWidgetContent: View {
    let entry: SpaceEntry
    let layout: SpaceWidgetLayout
    let renderingMode: WidgetRenderingMode
    let palette: SpacePalette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var foreground: Color { renderingMode == .fullColor ? palette.text : .primary }
    private var secondary: Color { renderingMode == .fullColor ? palette.secondaryText : .secondary }
    private var statusColor: Color { renderingMode == .fullColor ? entry.status.color(in: palette) : .primary }

    var body: some View {
        content
            .foregroundStyle(foreground)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .circular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: entry.status.symbolName)
                        .font(.title3)
                    Text(entry.status.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .padding(4)
            }
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: entry.name))
            .accessibilityValue(Text(entry.status.title))
        case .inline:
            // Keep the status first so a long space name cannot truncate it away.
            Label {
                Text("\(Text(entry.status.title)) · \(entry.name)")
            } icon: {
                Image(systemName: entry.status.symbolName)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: entry.name))
            .accessibilityValue(Text(entry.status.title))
        case .rectangular:
            VStack(alignment: .leading, spacing: 2) {
                name
                statusLabel.font(.caption.weight(.semibold))
                observation.font(.caption2)
            }
            .accessibilityElement(children: .combine)
        case .medium:
            HStack(alignment: .top, spacing: SpaceLayout.rowSpacing) {
                summary
                if !entry.rooms.isEmpty || entry.roomsUnavailable {
                    Rectangle()
                        .fill(renderingMode == .fullColor ? palette.border : .secondary)
                        .frame(width: 1)
                        .accessibilityHidden(true)
                    rooms
                }
            }
        case .small:
            summary
        }
    }

    private var name: some View {
        Text(verbatim: entry.name)
            .font(.headline)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1 : 2)
            .accessibilityLabel(Text(verbatim: entry.name))
            .accessibilityAddTraits(.isHeader)
    }

    private var statusLabel: some View {
        Label {
            Text(entry.status.title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } icon: {
            Image(systemName: entry.status.symbolName)
                .accessibilityHidden(true)
        }
        .foregroundStyle(statusColor)
        .widgetAccentable()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            name
            statusLabel.font(.title3.weight(.semibold))
            Spacer(minLength: 0)
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    if let since = entry.since, entry.status != .unknown, since <= entry.date {
                        Text("Changed \(since, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(secondary)
                    }
                    observation.font(.caption2)
                }
                .fixedSize(horizontal: false, vertical: true)
                observation.font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: 0).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var observation: some View {
        if let observedAt = entry.observedAt {
            Text("Observed \(observedAt, format: .dateTime.day().month().hour().minute())")
                .foregroundStyle(secondary)
        } else {
            Text("No current observation")
                .foregroundStyle(secondary)
        }
    }

    private var rooms: some View {
        ViewThatFits(in: .vertical) {
            roomList(limit: 5)
            roomList(limit: 3)
            roomList(limit: 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func roomList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Rooms")
                .font(.caption.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if entry.roomsUnavailable {
                Text("No current room data")
                    .font(.caption2)
                    .foregroundStyle(secondary)
            }
            ForEach(entry.rooms.prefix(limit)) { room in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: room.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityLabel(Text(verbatim: room.name))
                    Label {
                        Text(room.state.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    } icon: {
                        Image(systemName: room.state.widgetSymbol)
                            .accessibilityHidden(true)
                    }
                    .font(.caption2)
                    .foregroundStyle(renderingMode == .fullColor ? room.state.color(in: palette) : .primary)
                    .widgetAccentable()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SpaceWidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if renderingMode == .fullColor {
            SpacePalette(colorScheme: colorScheme, contrast: contrast).surface
        } else {
            Color.clear
        }
    }
}

private extension MainframeRoomState {
    var widgetSymbol: String {
        switch self {
        case .open: "door.left.hand.open"
        case .openPlus: "plus.circle"
        case .closed: "door.left.hand.closed"
        case .keyholder: "key.fill"
        case .member: "person.2.fill"
        case .closing: "clock"
        case .unknown: "questionmark.square.dashed"
        }
    }
}
