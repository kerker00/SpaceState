import MainframeStatus
import SpaceAPI
import SwiftUI

/// The window that opens from the menu bar icon.
struct StatusPanel: View {
    var store: StatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let message = store.info?.state?.message, store.lastError == nil {
                Text(message)
                    .foregroundStyle(.secondary)
            }

            if !store.rooms.isEmpty {
                Divider()
                rooms
            }

            if let error = store.lastError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Divider()
            footer
        }
        .padding()
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: store.status.symbolName)
                .font(.title)
                .foregroundStyle(store.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.info?.name ?? store.endpoint.host() ?? "")
                    .font(.headline)
                Text(store.status.title)
                    .foregroundStyle(store.status.color)
                if let since = store.info?.state?.lastChange, store.lastError == nil {
                    Text("Changed \(since, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var rooms: some View {
        Grid(alignment: .leading, verticalSpacing: 6) {
            ForEach(store.rooms) { room in
                GridRow {
                    StatusDot(color: room.state.color)
                    Text(room.name)
                    Text(room.state.title)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdate = store.lastUpdate {
                Text("Updated \(lastUpdate, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            .disabled(store.isRefreshing)
            if let website = store.info?.website {
                Link(destination: website) {
                    Image(systemName: "safari")
                }
                .help("Open website")
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
