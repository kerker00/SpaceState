import MainframeStatus
import SpaceAPI
import SwiftUI

/// The app's main screen: the selected space's state and, for Mainframe, its rooms.
struct StatusView: View {
    var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    if let message = store.info?.state?.message, store.lastError == nil {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                if !store.rooms.isEmpty {
                    Section("Rooms") {
                        ForEach(store.rooms) { room in
                            HStack {
                                StatusDot(color: room.state.color)
                                Text(room.name)
                                Spacer()
                                Text(room.state.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = store.lastError {
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }

                if let website = store.info?.website {
                    Section {
                        Link(destination: website) {
                            Label("Website", systemImage: "safari")
                        }
                    }
                }
            }
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsSheet(store: store, directory: directory, push: push)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: store.status.symbolName)
                .font(.largeTitle)
                .foregroundStyle(store.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.status.title)
                    .font(.title2.bold())
                    .foregroundStyle(store.status.color)
                if let since = store.info?.state?.lastChange, store.lastError == nil {
                    Text("Changed \(since, format: .relative(presentation: .named))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
