import SpaceAPI
import SwiftUI

/// Information a space publishes, shared by the phone app and the Mac's detail window.
struct SpaceDetailsView: View {
    var info: SpaceInfo
    #if os(macOS)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpaceDetailsPalette {
        SpaceDetailsPalette(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
    }
    #endif

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let address = text(info.location?.address) {
                    SpaceDetailsCard("Address", palette: palette) {
                        Text(address)
                            .textSelection(.enabled)
                    }
                }

                if let hint = text(info.location?.hint) {
                    SpaceDetailsCard("Access", palette: palette) {
                        Text(hint)
                            .textSelection(.enabled)
                    }
                }

                let contacts = SpaceDetailLink.contacts(for: info.contact)
                if !contacts.isEmpty {
                    SpaceDetailsCard("Contacts", palette: palette) {
                        linkRows(contacts)
                    }
                }

                ForEach(Array(keymasters.enumerated()), id: \.offset) { _, keymaster in
                    SpaceDetailsCard("Keyholder", palette: palette) {
                        if let name = text(keymaster.name) {
                            Text(name)
                                .font(SpaceDetailsFont.body.weight(.semibold))
                        }
                        if let nickname = text(keymaster.ircNick) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("IRC nickname")
                                    .font(SpaceDetailsFont.label)
                                    .foregroundStyle(palette.label)
                                Text(nickname)
                                    .textSelection(.enabled)
                            }
                        }
                        linkRows(SpaceDetailLink.contacts(for: SpaceInfo.Contact(
                            email: keymaster.email, phone: keymaster.phone,
                            matrix: keymaster.matrix, mastodon: keymaster.mastodon, xmpp: keymaster.xmpp
                        )))
                    }
                }

                let feeds = SpaceDetailLink.feeds(for: info.feeds)
                if !feeds.isEmpty {
                    SpaceDetailsCard("Feeds", palette: palette) {
                        linkRows(feeds)
                    }
                }

                if let website = info.website {
                    SpaceDetailsCard("Website", palette: palette) {
                        MacSpaceDetailLinkRow(link: SpaceDetailLink(
                            id: "website", title: "Website", value: website.absoluteString,
                            destination: website, symbolName: "safari"
                        ), palette: palette)
                    }
                }
            }
            .font(SpaceDetailsFont.body)
            .foregroundStyle(palette.text)
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(palette.background)
        .navigationTitle(info.name)
        #else
        List {
            if let address = text(info.location?.address) {
                SpaceDetailsSection("Address") {
                    Text(address)
                        .textSelection(.enabled)
                }
            }

            if let hint = text(info.location?.hint) {
                SpaceDetailsSection("Access") {
                    Text(hint)
                        .textSelection(.enabled)
                }
            }

            let contacts = SpaceDetailLink.contacts(for: info.contact)
            if !contacts.isEmpty {
                SpaceDetailsSection("Contacts") {
                    ForEach(contacts) { link in
                        SpaceDetailLinkRow(link: link)
                    }
                }
            }

            ForEach(Array(keymasters.enumerated()), id: \.offset) { _, keymaster in
                SpaceDetailsSection("Keyholder") {
                    if let name = text(keymaster.name) {
                        Text(name)
                            .font(.headline)
                    }
                    if let nickname = text(keymaster.ircNick) {
                        LabeledContent("IRC nickname") {
                            Text(nickname)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                    ForEach(SpaceDetailLink.contacts(for: SpaceInfo.Contact(
                        email: keymaster.email, phone: keymaster.phone,
                        matrix: keymaster.matrix, mastodon: keymaster.mastodon, xmpp: keymaster.xmpp
                    ))) { link in
                        SpaceDetailLinkRow(link: link)
                    }
                }
            }

            let feeds = SpaceDetailLink.feeds(for: info.feeds)
            if !feeds.isEmpty {
                SpaceDetailsSection("Feeds") {
                    ForEach(feeds) { link in
                        SpaceDetailLinkRow(link: link)
                    }
                }
            }

            if let website = info.website {
                Section {
                    Link(destination: website) {
                        HStack {
                            Label("Website", systemImage: "safari")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .accessibilityHidden(true)
                        }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.primary)
        .listStyle(.insetGrouped)
        .navigationTitle(info.name)
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func linkRows(_ links: [SpaceDetailLink]) -> some View {
        ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
            if index > 0 {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            MacSpaceDetailLinkRow(link: link, palette: palette)
        }
    }
    #endif

    private var keymasters: [SpaceInfo.Keymaster] {
        info.contact.keymasters.filter { person in
            [person.name, person.ircNick, person.phone, person.email, person.xmpp, person.mastodon, person.matrix]
                .contains { text($0) != nil }
        }
    }

    private func text(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

#if os(macOS)
private struct SpaceDetailsCard<Content: View>: View {
    let title: LocalizedStringResource
    let palette: SpaceDetailsPalette
    let content: Content

    init(_ title: LocalizedStringResource, palette: SpaceDetailsPalette, @ViewBuilder content: () -> Content) {
        self.title = title
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(SpaceDetailsFont.heading)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}

private struct MacSpaceDetailLinkRow: View {
    var link: SpaceDetailLink
    var palette: SpaceDetailsPalette

    var body: some View {
        if let destination = link.destination {
            Link(destination: destination) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
                .textSelection(.enabled)
        }
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: link.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(link.title)
                    .font(SpaceDetailsFont.label)
                    .foregroundStyle(palette.label)
                Text(link.value)
                    .font(SpaceDetailsFont.body.weight(.medium))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if link.destination != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private enum SpaceDetailsFont {
    static let body = Font.system(size: 15)
    static let label = Font.system(size: 13, weight: .semibold)
    static let heading = Font.system(size: 17, weight: .bold)
}

/// Opaque, contrasting surfaces avoid inactive-window dimming of secondary list text.
/// The palette follows system appearance and its increased-contrast preference.
private struct SpaceDetailsPalette {
    let background: Color
    let surface: Color
    let text: Color
    let label: Color
    let border: Color
    let accent: Color

    init(dark: Bool, increasedContrast: Bool) {
        background = dark ? Color(red: 15 / 255, green: 18 / 255, blue: 23 / 255) : Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
        surface = dark ? Color(red: 32 / 255, green: 38 / 255, blue: 48 / 255) : .white
        text = dark ? Color(red: 243 / 255, green: 245 / 255, blue: 247 / 255) : Color(red: 23 / 255, green: 32 / 255, blue: 43 / 255)
        label = increasedContrast ? text : (dark ? Color(red: 199 / 255, green: 208 / 255, blue: 221 / 255) : Color(red: 53 / 255, green: 67 / 255, blue: 85 / 255))
        border = increasedContrast ? text : (dark ? Color(red: 75 / 255, green: 87 / 255, blue: 104 / 255) : Color(red: 197 / 255, green: 202 / 255, blue: 211 / 255))
        accent = dark ? Color(red: 140 / 255, green: 198 / 255, blue: 255 / 255) : Color(red: 20 / 255, green: 94 / 255, blue: 168 / 255)
    }
}
#else
private struct SpaceDetailsSection<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

private struct SpaceDetailLinkRow: View {
    var link: SpaceDetailLink

    var body: some View {
        if let destination = link.destination {
            Link(destination: destination) {
                HStack {
                    label
                    Spacer(minLength: 12)
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            label
                .textSelection(.enabled)
        }
    }

    private var label: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(link.value)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: link.symbolName)
                .foregroundStyle(.primary)
        }
    }
}
#endif
