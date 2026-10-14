import SpaceAPI
import SwiftUI

/// The same selectable directory content on iPhone and Mac. The caller supplies
/// the effective C-01 state; raw last-known flags never determine the color.
struct SpaceSelectionRow: View {
    let name: String
    let address: String?
    let status: SpaceStatus
    let observedAt: Date?
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)

        SpaceCard {
            HStack(alignment: .top, spacing: SpaceLayout.rowSpacing) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: status.symbolName)
                        .font(.title3)
                        .foregroundStyle(status.color(in: palette))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: name)
                        .font(SpaceTypography.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status.title)
                        .font(SpaceTypography.label)
                        .foregroundStyle(status.color(in: palette))
                        .fixedSize(horizontal: false, vertical: true)
                    if let observedAt {
                        Text("Observed \(observedAt, format: .dateTime.day().month().hour().minute())")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No current observation")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: address)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: SpaceLayout.minimumControlHeight, alignment: .leading)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: SpaceLayout.cardCornerRadius)
                    .strokeBorder(palette.accent, lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
