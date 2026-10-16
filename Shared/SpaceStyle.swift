import SwiftUI

/// Shared app colors, aligned with the website's paper, slate and amber palette.
/// Opaque surfaces keep text readable even when a Mac window is inactive.
struct SpacePalette {
    let background: Color
    let surface: Color
    let text: Color
    let secondaryText: Color
    let border: Color
    let accent: Color
    let statusOpen: Color
    let statusClosed: Color
    let statusUnknown: Color

    init(colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        let dark = colorScheme == .dark
        let increasedContrast = contrast == .increased

        background = Self.color(dark ? 0x151a22 : 0xf4f3ee)
        surface = Self.color(dark ? 0x1e2530 : 0xfbfaf7)
        text = Self.color(dark ? 0xf4f3ee : 0x252d38)
        secondaryText = increasedContrast ? text : Self.color(dark ? 0xb7c0ce : 0x5e6570)
        border = increasedContrast ? text : Self.color(dark ? 0x394353 : 0xced0d2)
        accent = Self.color(dark ? 0xfac276 : 0x925400)
        statusOpen = Self.color(dark ? 0xaad77c : 0x4f723b)
        statusClosed = Self.color(dark ? 0xff9b8b : 0xad3d31)
        statusUnknown = secondaryText
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xff) / 255,
              green: Double((hex >> 8) & 0xff) / 255,
              blue: Double(hex & 0xff) / 255,
              opacity: 1)
    }
}

enum SpaceLayout {
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let cardSpacing: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let minimumControlHeight: CGFloat = 44
    static let readableWidth: CGFloat = 720
}

enum SpaceTypography {
    #if os(macOS)
    static let body = Font.system(size: 15)
    static let label = Font.system(size: 13, weight: .semibold)
    static let heading = Font.system(size: 17, weight: .bold)
    static let status = Font.system(size: 24, weight: .bold)
    #else
    static let body = Font.body
    static let label = Font.subheadline.weight(.semibold)
    static let heading = Font.title3.bold()
    static let status = Font.title.bold()
    #endif
}

/// A section surface usable by both detail and status views.
struct SpaceCard<Content: View>: View {
    let title: LocalizedStringResource?
    let showsBorder: Bool
    let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ title: LocalizedStringResource? = nil, showsBorder: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsBorder = showsBorder
        self.content = content()
    }

    var body: some View {
        let palette = SpacePalette(colorScheme: colorScheme, contrast: contrast)
        let shape = RoundedRectangle(cornerRadius: SpaceLayout.cardCornerRadius)

        VStack(alignment: .leading, spacing: SpaceLayout.cardSpacing) {
            if let title {
                Text(title)
                    .font(SpaceTypography.heading)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .font(SpaceTypography.body)
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpaceLayout.cardPadding)
        .background(palette.surface, in: shape)
        .overlay {
            if showsBorder {
                shape.strokeBorder(palette.border, lineWidth: 1)
            }
        }
    }
}
