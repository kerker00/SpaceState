import SpaceAPI
import SwiftUI

struct SettingsSheet: View {
    @Bindable var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SpacePicker(store: store, directory: directory)
                    } label: {
                        LabeledContent("Space", value: store.info?.name ?? store.endpoint.host() ?? "")
                    }
                    Picker("Check every", selection: $store.refreshInterval) {
                        ForEach(StatusStore.refreshIntervals, id: \.self) { interval in
                            Text(Duration.UnitsFormatStyle(allowedUnits: [.minutes], width: .wide).format(interval))
                                .tag(interval)
                        }
                    }
                }

                Section {
                    Toggle("Notify me when the state changes", isOn: notificationsEnabled)
                } footer: {
                    if let message = push.status.message {
                        Text(message)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var notificationsEnabled: Binding<Bool> {
        Binding(
            get: { push.isEnabled },
            set: { enabled in Task { await push.setEnabled(enabled) } }
        )
    }
}

private struct SpacePicker: View {
    var store: StatusStore
    var directory: DirectoryStore
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(directory.entries(matching: query)) { entry in
            Button {
                store.endpoint = entry.endpoint
                dismiss()
            } label: {
                HStack {
                    StatusDot(color: entry.info.status.color)
                    VStack(alignment: .leading) {
                        Text(entry.info.name)
                            .foregroundStyle(.primary)
                        if let address = entry.info.location?.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if entry.endpoint == store.endpoint {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search spaces")
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
        .navigationTitle("Space")
        .task {
            if directory.entries.isEmpty { await directory.load() }
        }
    }
}
