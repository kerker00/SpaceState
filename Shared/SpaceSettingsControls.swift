import SwiftUI

/// Presentation-only controls: the owning screen keeps the existing settings,
/// notification and retry bindings and actions.
struct SpaceRefreshControl: View {
    @Binding var interval: Duration
    let options: [Duration]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
                    Text("Check every")
                        .font(SpaceTypography.label)
                        .accessibilityHidden(true)
                    picker.labelsHidden()
                        .accessibilityLabel(Text("Check every"))
                }
            } else {
                picker
            }
        }
        .font(SpaceTypography.body)
    }

    private var picker: some View {
        Picker("Check every", selection: $interval) {
            ForEach(options, id: \.self) { option in
                Text(Duration.UnitsFormatStyle(allowedUnits: [.minutes], width: .wide).format(option))
                    .tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}

struct SpaceNotificationControl: View {
    @Binding var isEnabled: Bool
    let message: LocalizedStringKey?
    let canRetry: Bool
    let retry: () -> Void
    var canOpenSettings = false
    var openSettings: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)

        VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
            Toggle(isOn: $isEnabled) {
                Text("Notify me when the state changes")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message)
                    .font(SpaceTypography.label)
                    .foregroundStyle(canRetry ? palette.statusClosed : palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canRetry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
            }
            if canOpenSettings {
                Button("Open notification settings", action: openSettings)
                    .buttonStyle(.bordered)
            }
        }
        .font(SpaceTypography.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.accent)
    }
}

struct SpaceDirectoryNotice: View {
    let isLoading: Bool
    let retry: () -> Void

    var body: some View {
        SpaceCard {
            VStack(alignment: .leading, spacing: SpaceLayout.compactSpacing) {
                Label("Directory unavailable; showing last known list", systemImage: "wifi.exclamationmark")
                    .font(SpaceTypography.label)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
            }
        }
    }
}
