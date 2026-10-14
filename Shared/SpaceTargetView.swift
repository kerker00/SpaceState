import SwiftUI
import SpaceAPI
import MainframeStatus

/// A fresh view of an explicitly opened space, separate from selection/settings.
struct SpaceTargetView: View {
    let destination: SpaceNavigation.Destination
    var close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var store: StatusStore { destination.store }
    private var palette: SpacePalette { SpacePalette(colorScheme: colorScheme, contrast: contrast) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List {
                    SpaceStatusCard(status: store.status,
                        name: store.info?.name ?? store.endpoint.host() ?? "",
                        changedAt: store.lastError == nil && store.freshness == .current ? store.info?.state?.lastChange : nil,
                        message: store.lastError == nil && store.freshness == .current ? store.info?.state?.message : nil)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if !store.rooms.isEmpty {
                        SpaceRoomsCard(rooms: store.displayRooms, observedAt: store.roomsTiming?.observedAt,
                            unavailable: store.lastRoomsError != nil || store.roomsFreshness != .current,
                            focusedRoomID: destination.target.room)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .id("target-rooms")
                    }
                    if let error = store.lastError {
                        Text(error.localizedDescription).foregroundStyle(palette.secondaryText)
                    } else if store.freshness != .current {
                        Text("No current observation").foregroundStyle(palette.secondaryText)
                    }
                    if let error = store.lastRoomsError {
                        Label("Rooms unavailable: \(error.localizedDescription)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(palette.secondaryText)
                    }
                    if let info = store.info {
                        NavigationLink {
                            SpaceDetailsView(info: info, timing: store.observationTiming, lastReadFailed: store.lastError != nil)
                        } label: {
                            Label("Space details", systemImage: "info.circle")
                        }
                    }
                    if let observed = store.observationTiming?.observedAt {
                        Text("Observed \(observed, format: .dateTime.day().month().hour().minute())")
                    }
                    if let attempt = store.lastAttempt {
                        Text("Last checked \(attempt, format: .dateTime.hour().minute())")
                    }
                    Text("Your selected space stays unchanged.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(palette.background)
                .foregroundStyle(palette.text)
                .tint(palette.accent)
                .refreshable { await store.refresh() }
                .onChange(of: store.rooms.map(\.id), initial: true) { _, ids in
                    if let room = destination.target.room, ids.contains(room) {
                        scroll.scrollTo("target-rooms", anchor: .top)
                    }
                }
            }
            .navigationTitle(store.info?.name ?? store.endpoint.host() ?? "SpaceState")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .disabled(store.isRefreshing)
                }
            }
        }
        .task { store.resumePolling() }
        .onDisappear { store.pausePolling() }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 500)
        #endif
    }
}
