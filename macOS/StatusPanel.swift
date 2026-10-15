import MainframeStatus
import SpaceAPI
import SwiftUI

/// The window that opens from the menu bar icon.
struct StatusPanel: View {
    var store: StatusStore
    var showDetails: () -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette {
        SpacePalette(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        ScrollView {
            content
        }
        // A menu-bar window needs a concrete size: a maximum height alone can
        // collapse the scroll view during the hosting window's initial sizing.
        .frame(width: 380, height: 640)
        .background(palette.background)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SpaceLayout.sectionSpacing) {
            SpaceStatusCard(
                status: store.status,
                name: store.info?.name ?? store.endpoint.host() ?? "",
                changedAt: store.lastError == nil && store.freshness == .current ? store.info?.state?.lastChange : nil,
                message: store.lastError == nil && store.freshness == .current ? store.info?.state?.message : nil
            )

            if !store.rooms.isEmpty {
                SpaceRoomsCard(rooms: store.displayRooms, observedAt: store.roomsTiming?.observedAt,
                    unavailable: store.lastRoomsError != nil || store.roomsFreshness != .current)
            }

            if let info = store.info, !SpaceSensorPresentation(info.sensors).summary.isEmpty {
                SpaceSensorsCard(sensors: info.sensors, timing: store.observationTiming,
                    failed: store.lastError != nil)
            }

            if store.info != nil && store.lastError == nil && store.freshness != .current {
                Text("No current observation").font(SpaceTypography.label)
            }
            if let error = store.lastRoomsError {
                SpaceCard {
                    Label("Rooms unavailable: \(error.localizedDescription)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(palette.secondaryText)
                }
            }

            if let error = store.lastError {
                SpaceCard {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(palette.secondaryText)
                }
            }

            footer
        }
        .font(SpaceTypography.body)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .padding(SpaceLayout.pagePadding)
        .background(palette.background)
    }

    private var footer: some View {
        HStack {
            if store.observationTiming != nil || store.lastAttempt != nil {
                VStack(alignment: .leading) {
                    if let observedAt = store.observationTiming?.observedAt {
                        Text("Observed \(observedAt, format: .dateTime.day().month().hour().minute())")
                    }
                    if let attempt = store.lastAttempt {
                        Text("Last checked \(attempt, format: .dateTime.hour().minute())")
                    }
                }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            .disabled(store.isRefreshing)
            if store.info != nil {
                Button("Space details", systemImage: "info.circle") {
                    showDetails()
                }
                .help("Space details")
            }
            if let website = store.info?.website {
                Link(destination: website) {
                    Image(systemName: "safari")
                }
                .help("Open website")
            }
            // SettingsLink does not reliably bring the window to the front in an app
            // without a Dock icon, so activate the app first.
            Button("Settings", systemImage: "gearshape") {
                NSApplication.shared.activate()
                openSettings()
            }
            .help("Settings")
            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(palette.accent)
    }
}
