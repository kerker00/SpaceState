import MainframeStatus
import SpaceAPI
import SwiftUI

/// The window that opens from the menu bar icon.
struct StatusPanel: View {
    var store: StatusStore
    var showDetails: () -> Void
    var heightChanged: ((CGFloat) -> Void)? = nil
    @State private var contentHeight: CGFloat = 160
    @State private var footerHeight: CGFloat = 64
    @State private var availableHeight: CGFloat = 620
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette {
        SpacePalette(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeight = max(1, ceil($0))
                    }
            }
            .frame(height: min(contentHeight, max(80, availableHeight - footerHeight)))
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            footer
                .padding(.horizontal, SpaceLayout.pagePadding)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height + 1 } action: {
                    footerHeight = ceil($0)
                }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightChanged?($0) }
        .onAppear(perform: updateAvailableHeight)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateAvailableHeight()
        }
    }

    private func updateAvailableHeight() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        availableHeight = min(620, max(200, (screen?.visibleFrame.height ?? 800) - 40))
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
