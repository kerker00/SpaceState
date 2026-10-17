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
                VStack(alignment: .leading, spacing: SpaceLayout.sectionSpacing) {
                    SpaceStatusCard(
                        status: store.status,
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
                        Text("No current observation")
                    }
                    if let error = store.lastRoomsError {
                        Label("Rooms unavailable: \(error.localizedDescription)", systemImage: "exclamationmark.triangle")
                    }
                    if let error = store.lastError {
                        SpaceCard {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(palette.secondaryText)
                        }
                    }

                    if let info = store.info {
                        SpaceCard {
                            NavigationLink {
                                SpaceDetailsView(info: info, timing: store.observationTiming, lastReadFailed: store.lastError != nil)
                            } label: {
                                HStack {
                                    Label("Space details", systemImage: "info.circle")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(palette.secondaryText)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: SpaceLayout.minimumControlHeight)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if let website = info.website {
                                Divider()
                                Link(destination: website) {
                                    Label("Website", systemImage: "safari")
                                        .frame(maxWidth: .infinity, minHeight: SpaceLayout.minimumControlHeight, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, SpaceLayout.pagePadding)
                .padding(.vertical, SpaceLayout.sectionSpacing)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
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
    }
}
