import SpaceAPI
import SwiftUI

struct OnboardingView: View {
    var onboarding: OnboardingStore
    var store: StatusStore
    var directory: DirectoryStore
    var push: PushStore
    @State private var location = OnboardingLocation()
    @State private var suggestion: DirectoryEntry?
    @State private var locationUnavailable = false
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette { SpacePalette(colorScheme: colorScheme, contrast: contrast) }

    var body: some View {
        VStack(spacing: 0) {
            if onboarding.step == .space {
                spaceSelection
            } else {
                notificationSetup
            }
        }
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .background(palette.background)
        .task {
            if onboarding.step == .space { await directory.load() }
        }
        .onDisappear { location.cancel() }
    }

    private var spaceSelection: some View {
        // One scrolling surface keeps the introduction and search in the same
        // layout flow, including with the keyboard and accessibility text sizes.
        List {
            VStack(alignment: .leading, spacing: SpaceLayout.cardSpacing) {
                Text("SpaceState")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                SpaceCard { nearbySelection }
            }
            .padding(.vertical, SpaceLayout.compactSpacing)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
                Text("Choose your space")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TextField("Search spaces", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(directory.entries(matching: query)) { entry in
                Button { select(entry) } label: {
                    SpaceSelectionRow(name: entry.info.name, status: directory.status(for: entry), isSelected: false)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if directory.entries.isEmpty {
                directoryState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if directory.entries(matching: query).isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .padding(.horizontal, SpaceLayout.pagePadding)
    }

    private var nearbySelection: some View {
        VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
            if location.isRequesting {
                ProgressView("Finding a space…")
                Button("Search manually") { cancelLocation() }
                    .buttonStyle(SpaceActionButtonStyle())
            } else if let suggestion {
                Label("Nearby suggestion", systemImage: "location")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                Text(verbatim: suggestion.info.name).font(.headline)
                Button("Use this space") { select(suggestion) }
                    .buttonStyle(SpaceActionButtonStyle(prominent: true))
            } else if locationUnavailable {
                Text("No suggestion available. Search below.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Button("Find a nearby space", systemImage: "location") { findNearby() }
                    .buttonStyle(SpaceActionButtonStyle())
                    .disabled(directory.isLoading || directory.entries.isEmpty)
                Text("One-time location access. Nothing is saved or shared.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var directoryState: some View {
        if directory.isLoading {
            ProgressView().accessibilityLabel(Text("Space"))
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            ContentUnavailableView {
                Label("Spaces unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Connect to the internet to choose your space.")
            } actions: {
                Button("Try Again") { Task { await directory.load() } }
                    .buttonStyle(SpaceActionButtonStyle())
            }
        }
    }

    private var notificationSetup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceLayout.sectionSpacing) {
                Image(systemName: "bell.badge").font(.largeTitle).accessibilityHidden(true)
                Text("Stay up to date")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: onboarding.selectedName).font(.title2)
                Text("Get notified when your space opens or closes.")
                Text("Optional. Change this anytime in Settings.")
                    .foregroundStyle(palette.secondaryText)
                Button("Enable notifications") {
                    Task {
                        await onboarding.enableNotifications(using: push, store: store)
                    }
                }
                .buttonStyle(SpaceActionButtonStyle(prominent: true))
                .disabled(onboarding.isEnablingNotifications)
                if onboarding.isEnablingNotifications { ProgressView() }
                Button("Not now") { Task { await onboarding.skipNotifications(using: push) } }
                    .buttonStyle(SpaceActionButtonStyle())
                    .disabled(onboarding.isEnablingNotifications)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520, alignment: .leading)
            .padding(SpaceLayout.pagePadding)
        }
    }

    private func select(_ entry: DirectoryEntry) {
        location.cancel()
        suggestion = nil
        onboarding.select(entry, in: store)
        store.resumePolling()
    }

    private func cancelLocation() {
        location.cancel()
        suggestion = nil
        locationUnavailable = true
    }

    private func findNearby() {
        suggestion = nil
        locationUnavailable = false
        location.request { coordinate in
            guard onboarding.step == .space else { return }
            suggestion = coordinate.flatMap { OnboardingStore.nearest(in: directory.entries, to: $0) }
            locationUnavailable = suggestion == nil
        }
    }
}
