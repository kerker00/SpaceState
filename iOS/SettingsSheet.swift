import SpaceAPI
import SwiftUI

struct SettingsSheet: View {
    @Bindable var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var palette: SpacePalette { SpacePalette(colorScheme: colorScheme, contrast: contrast) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Space") {
                    NavigationLink {
                        SpacePicker(store: store, directory: directory)
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Space").font(.subheadline).foregroundStyle(palette.secondaryText)
                                Text(verbatim: selectedName)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            LabeledContent("Space") {
                                Text(verbatim: selectedName)
                                    .foregroundStyle(palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    SpaceRefreshControl(interval: $store.refreshInterval, options: StatusStore.refreshIntervals)
                }
                .listRowBackground(palette.surface)

                Section {
                    SpaceNotificationControl(isEnabled: notificationsEnabled, message: push.status.message,
                        canRetry: canRetryNotifications, retry: { push.retry() })
                }
                .listRowBackground(palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(palette.accent)
    }

    private var selectedName: String { store.info?.name ?? store.endpoint.host() ?? "" }
    private var canRetryNotifications: Bool {
        if case .failed = push.status { return true }
        return false
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette { SpacePalette(colorScheme: colorScheme, contrast: contrast) }
    private var entries: [DirectoryEntry] { directory.entries(matching: query) }

    var body: some View {
        List(entries) { entry in
            Button {
                store.endpoint = entry.endpoint
                dismiss()
            } label: {
                SpaceSelectionRow(name: entry.info.name,
                    isSelected: entry.endpoint == store.endpoint)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowSeparator(.visible)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .tint(palette.accent)
        .searchable(text: $query, prompt: "Search spaces")
        .overlay {
            if directory.isLoading && directory.entries.isEmpty {
                ProgressView().accessibilityLabel(Text("Space"))
            } else if let error = directory.lastError, directory.entries.isEmpty {
                ContentUnavailableView {
                    Label("Spaces unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try Again") { Task { await directory.load() } }
                }
            } else if !directory.entries.isEmpty && entries.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Space")
        .safeAreaInset(edge: .bottom) {
            if directory.lastError != nil && !directory.entries.isEmpty {
                SpaceDirectoryNotice(isLoading: directory.isLoading, retry: { Task { await directory.load() } })
                    .padding(.horizontal, SpaceLayout.pagePadding)
                    .padding(.bottom, SpaceLayout.compactSpacing)
            }
        }
        .task {
            await directory.load()
        }
    }
}
