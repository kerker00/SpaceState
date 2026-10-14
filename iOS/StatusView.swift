import MainframeStatus
import SpaceAPI
import SwiftUI

/// The app's main screen: the selected space's state and, for Mainframe, its rooms.
struct StatusView: View {
    var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
    var navigation: SpaceNavigation
    @State private var showsSettings = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette {
        SpacePalette(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SpaceStatusCard(
                        status: store.status,
                        changedAt: store.lastError == nil && store.freshness == .current ? store.info?.state?.lastChange : nil,
                        message: store.lastError == nil && store.freshness == .current ? store.info?.state?.message : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if !store.rooms.isEmpty {
                    Section {
                        SpaceRoomsCard(rooms: store.displayRooms, observedAt: store.roomsTiming?.observedAt,
                            unavailable: store.lastRoomsError != nil || store.roomsFreshness != .current)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                if store.info != nil && store.lastError == nil && store.freshness != .current {
                    Section { Text("No current observation") }
                }
                if let error = store.lastRoomsError {
                    Section { Label("Rooms unavailable: \(error.localizedDescription)", systemImage: "exclamationmark.triangle") }
                }

                if let error = store.lastError {
                    Section {
                        SpaceCard {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(palette.secondaryText)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                if let info = store.info {
                    Section {
                        NavigationLink {
                            SpaceDetailsView(info: info, timing: store.observationTiming, lastReadFailed: store.lastError != nil)
                        } label: {
                            Label("Space details", systemImage: "info.circle")
                        }
                        if let website = info.website {
                            Link(destination: website) {
                                Label("Website", systemImage: "safari")
                            }
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(SpaceLayout.sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .refreshable {
                await store.refresh()
            }
            .navigationTitle(store.info?.name ?? store.endpoint.host() ?? "")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                }
                if store.observationTiming != nil || store.lastAttempt != nil {
                    ToolbarItem(placement: .status) {
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
                }
            }
            .sheet(isPresented: Binding(
                get: { showsSettings || navigation.destination != nil },
                set: { if !$0 { showsSettings = false; navigation.close() } }
            )) {
                if let destination = navigation.destination {
                    SpaceTargetView(destination: destination) {
                        showsSettings = false
                        navigation.close()
                    }
                    .id(destination.id)
                } else {
                    SettingsSheet(store: store, directory: directory, push: push)
                }
            }
            .onChange(of: navigation.destination?.id) { _, id in
                if id != nil { showsSettings = false }
            }
        }
    }
}
