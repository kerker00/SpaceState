import ServiceManagement
import SpaceAPI
import SwiftUI

struct SettingsView: View {
    var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
    @State private var selectedTab: SettingsTab = .space
    @State private var generalHeight: CGFloat = 0
    @State private var generalViewportHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)

        TabView(selection: $selectedTab) {
            Tab("Space", systemImage: "building.2", value: SettingsTab.space) {
                SpacePicker(store: store, directory: directory)
                    .toolbarBackground(palette.background, for: .windowToolbar)
                    .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            }
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettings(store: store, push: push,
                    showsScrollIndicator: generalHeight > generalViewportHeight + 0.5,
                    heightChanged: { generalHeight = $0 },
                    viewportHeightChanged: { generalViewportHeight = $0 })
                    .toolbarBackground(palette.background, for: .windowToolbar)
                    .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            }
        }
        .tint(palette.accent)
        .background(palette.background)
        .containerBackground(palette.background, for: .window)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: .infinity,
               minHeight: 320, idealHeight: 480, maxHeight: .infinity)
        .background(MacWindowSizing(preferredHeight: 480,
            minimum: NSSize(width: 480, height: 320),
            contentFit: selectedTab == .general ? .init(contentHeight: generalHeight, viewportHeight: generalViewportHeight) : nil,
            maximumHeight: selectedTab == .general ? nil : 680))
    }

    private enum SettingsTab: Hashable { case space, general }
}

private struct SpacePicker: View {
    var store: StatusStore
    var directory: DirectoryStore
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette { SpacePalette(colorScheme: colorScheme, contrast: contrast) }
    var body: some View {
        let entries = directory.entries(matching: query)
        VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
            TextField("Search spaces", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(SpaceTypography.body)

            List(entries, selection: selection) { entry in
                SpaceSelectionRow(name: entry.info.name,
                    status: directory.status(for: entry),
                    isSelected: entry.endpoint == store.endpoint)
                    .tag(entry.endpoint)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            if directory.lastError != nil && !directory.entries.isEmpty {
                SpaceDirectoryNotice(isLoading: directory.isLoading, retry: { Task { await directory.load() } })
            }
        }
        .padding(SpaceLayout.pagePadding)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .background(palette.background)
        .task {
            await directory.load()
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
    var push: PushStore
    var showsScrollIndicator = true
    var heightChanged: ((CGFloat) -> Void)? = nil
    var viewportHeightChanged: ((CGFloat) -> Void)? = nil
    @AppStorage(DockIcon.defaultsKey) private var showDockIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette { SpacePalette(colorScheme: colorScheme, contrast: contrast) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceLayout.sectionSpacing) {
                SpaceCard("Space") {
                    SpaceRefreshControl(interval: $store.refreshInterval, options: StatusStore.refreshIntervals)
                }
                SpaceCard("General") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLoginItem(enabled: enabled)
                        }
                    if let loginItemError {
                        Text(loginItemError)
                            .font(SpaceTypography.label)
                            .foregroundStyle(palette.statusClosed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Show in Dock", isOn: $showDockIcon)
                        .onChange(of: showDockIcon) { _, visible in
                            DockIcon.apply(visible: visible)
                        }
                }
                SpaceCard {
                    SpaceNotificationControl(isEnabled: notificationsEnabled, message: push.status.message,
                        canRetry: canRetryNotifications, retry: { push.retry() },
                        canOpenSettings: push.status == .denied, openSettings: { push.openSystemSettings() })
                }
            }
            .padding(SpaceLayout.pagePadding)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightChanged?($0) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeightChanged?($0) }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(showsScrollIndicator ? .automatic : .hidden)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .background(palette.background)
    }

    private var canRetryNotifications: Bool {
        if case .failed = push.status { return true }
        return false
    }
    private var notificationsEnabled: Binding<Bool> {
        Binding(
            get: { push.isEnabled },
            set: { enabled in Task {
                await push.setEnabled(enabled)
                if enabled && push.status == .denied { push.openSystemSettings() }
            } }
        )
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
