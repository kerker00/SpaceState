import SpaceAPI
import SwiftUI

/// A flat selection row with the effective status from directory observations.
struct SpaceSelectionRow: View {
    let name: String
    let status: SpaceStatus
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)

        HStack(spacing: SpaceLayout.compactSpacing) {
            StatusDot(color: status == .unknown ? unknownDot(in: palette) : status.color(in: palette))
            Text(verbatim: name)
                .font(SpaceTypography.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 18)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: SpaceLayout.minimumControlHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(status.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(Text(status.title))
    }

    private func unknownDot(in palette: SpacePalette) -> Color {
        // Use an existing light neutral for the dot, while status text elsewhere
        // retains its stronger contrast. Increased contrast follows the palette.
        colorScheme == .dark || contrast == .increased ? palette.statusUnknown : palette.border
    }
}
