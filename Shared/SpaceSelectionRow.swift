import SpaceAPI
import SwiftUI

/// The same selectable directory content on iPhone and Mac. The caller supplies
/// the effective C-01 state; raw last-known flags never determine the color.
struct SpaceSelectionRow: View {
    let name: String
    let status: SpaceStatus
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)

        HStack(spacing: SpaceLayout.compactSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name)
                    .font(SpaceTypography.body.weight(.medium))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    statusLabel(palette: palette)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                statusLabel(palette: palette)
                    .fixedSize()
            }
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
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func statusLabel(palette: SpacePalette) -> some View {
        HStack(spacing: 5) {
            StatusDot(color: status.color(in: palette))
            Text(status.title)
                .foregroundStyle(status.color(in: palette))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(SpaceTypography.label)
    }
}
