import MainframeStatus
import SpaceAPI
import SwiftUI

/// The same status summary in the iPhone screen and both Mac status surfaces.
struct SpaceStatusCard: View {
    var status: SpaceStatus
    var name: String? = nil
    var changedAt: Date? = nil
    var message: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.spaceAppearance) private var appearance

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast, appearance: appearance)
        let statusColor = status.color(in: palette)

        SpaceCard(showsBorder: showsBorder) {
            HStack(alignment: .top, spacing: SpaceLayout.rowSpacing) {
                Image(systemName: status.symbolName)
                    .font(.largeTitle)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    if let name {
                        Text(name)
                            .font(SpaceTypography.label)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Text(status.title)
                        .font(appearance == .menuBar ? .title2.bold() : SpaceTypography.status)
                        .foregroundStyle(statusColor)
                        .accessibilityAddTraits(.isHeader)
                    if let changedAt {
                        Text("Changed \(changedAt, format: .relative(presentation: .named))")
                            .font(SpaceTypography.label)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var showsBorder: Bool {
        #if os(iOS)
        // Keep the prominent iPhone status surface unoutlined. Section cards
        // below it retain their own fine borders.
        false
        #else
        true
        #endif
    }
}

struct SpaceRoomsCard: View {
    var rooms: [MainframeRoom]
    var observedAt: Date? = nil
    var unavailable = false
    var focusedRoomID: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.spaceAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast, appearance: appearance)

        SpaceCard("Rooms") {
            if unavailable {
                Text("No current room data")
                    .font(SpaceTypography.label)
                    .foregroundStyle(palette.secondaryText)
            }
            if let observedAt {
                Text("Observed \(observedAt, format: .dateTime.day().month().hour().minute())")
                    .font(SpaceTypography.label)
                    .foregroundStyle(palette.secondaryText)
            }
            VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.border)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    roomRow(room, palette: palette)
                        .padding(.vertical, 2)
                        .padding(.horizontal, room.id == focusedRoomID ? 8 : 0)
                        .overlay {
                            if room.id == focusedRoomID {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(palette.accent, lineWidth: 1.5)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(room.id == focusedRoomID ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private func roomRow(_ room: MainframeRoom, palette: SpacePalette) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                roomName(room, palette: palette)
                Text(room.state.title)
                    .font(SpaceTypography.label)
                    .foregroundStyle(room.state.color(in: palette))
                    .padding(.leading, 8 + SpaceLayout.rowSpacing)
            }
        } else {
            HStack(spacing: SpaceLayout.rowSpacing) {
                roomName(room, palette: palette)
                Spacer(minLength: SpaceLayout.rowSpacing)
                Text(room.state.title)
                    .font(SpaceTypography.label)
                    .foregroundStyle(room.state.color(in: palette))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func roomName(_ room: MainframeRoom, palette: SpacePalette) -> some View {
        HStack(spacing: SpaceLayout.rowSpacing) {
            StatusDot(color: room.state.color(in: palette))
            Text(room.name)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
