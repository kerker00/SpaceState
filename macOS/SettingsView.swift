import ServiceManagement
import SpaceAPI
import SwiftUI

struct SettingsView: View {
    var store: StatusStore
    var directory: DirectoryStore

    var body: some View {
        TabView {
            Tab("Space", systemImage: "building.2") {
                SpacePicker(store: store, directory: directory)
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(store: store)
            }
        }
        .frame(width: 460, height: 420)
    }
}

private struct SpacePicker: View {
    var store: StatusStore
    var directory: DirectoryStore
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Search spaces", text: $query)
                .textFieldStyle(.roundedBorder)

            List(directory.entries(matching: query), selection: selection) { entry in
                HStack {
                    StatusDot(color: entry.info.status.color)
                    VStack(alignment: .leading) {
                        Text(entry.info.name)
                        if let address = entry.info.location?.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(entry.endpoint)
            }
            .overlay {
                if directory.isLoading && directory.entries.isEmpty {
                    ProgressView()
                } else if let error = directory.lastError, directory.entries.isEmpty {
                    ContentUnavailableView {
                        Label("Spaces unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Try Again") { Task { await directory.load() } }
                    }
                }
            }
        }
        .padding()
        .task {
            if directory.entries.isEmpty { await directory.load() }
        }
    }

    private var selection: Binding<URL?> {
        Binding(
            get: { store.endpoint },
            set: { if let endpoint = $0 { store.endpoint = endpoint } }
        )
    }
}

private struct GeneralSettings: View {
    @Bindable var store: StatusStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Picker("Check every", selection: $store.refreshInterval) {
                ForEach(StatusStore.refreshIntervals, id: \.self) { interval in
                    Text(Duration.UnitsFormatStyle(allowedUnits: [.minutes], width: .wide).format(interval))
                        .tag(interval)
                }
            }

            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLoginItem(enabled: enabled)
                }

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
