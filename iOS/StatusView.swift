import MainframeStatus
import SpaceAPI
import SwiftUI

/// The app's main screen: the selected space's state and, for Mainframe, its rooms.
struct StatusView: View {
    var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
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
                        changedAt: store.lastError == nil ? store.info?.state?.lastChange : nil,
                        message: store.lastError == nil ? store.info?.state?.message : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if !store.rooms.isEmpty {
                    Section {
                        SpaceRoomsCard(rooms: store.rooms)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
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
                            SpaceDetailsView(info: info)
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
                if let lastUpdate = store.lastUpdate {
                    ToolbarItem(placement: .status) {
                        Text("Updated \(lastUpdate, format: .dateTime.hour().minute())")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsSheet(store: store, directory: directory, push: push)
            }
        }
    }
}
