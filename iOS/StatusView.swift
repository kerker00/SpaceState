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

                if let info = store.info, !SpaceSensorPresentation(info.sensors).summary.isEmpty {
                    Section {
                        SpaceSensorsCard(sensors: info.sensors, timing: store.observationTiming,
                            failed: store.lastError != nil)
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
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .refreshable {
                await store.refresh()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let observedAt = store.observationTiming?.observedAt {
                    observationFooter(observedAt)
                }
            }
            .background(palette.background)
            .navigationTitle(store.info?.name ?? store.endpoint.host() ?? "")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
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

    private func observationFooter(_ observedAt: Date) -> some View {
        Text("Observed \(observedAt, format: .dateTime.day().month().hour().minute())")
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SpaceLayout.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}
