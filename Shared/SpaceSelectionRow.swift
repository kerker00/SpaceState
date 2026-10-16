import SwiftUI

/// A plain selection row; directory evidence is not presented as a live status.
struct SpaceSelectionRow: View {
    let name: String
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)

        HStack(spacing: SpaceLayout.compactSpacing) {
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}
