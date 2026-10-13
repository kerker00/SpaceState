import SpaceAPI
import SwiftUI

/// Information a space publishes, shared by the phone app and the Mac's detail window.
struct SpaceDetailsView: View {
    var info: SpaceInfo
    var timing: ObservationTiming? = nil
    var lastReadFailed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: SpacePalette {
        SpacePalette(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceLayout.sectionSpacing) {
                if let timing {
                    SpaceCard("Observation") {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            if lastReadFailed || timing.freshness(at: context.date) != .current {
                                Text("Showing last known details")
                                    .foregroundStyle(palette.secondaryText)
                            }
                            if let observedAt = timing.observedAt {
                                Text("Observed \(observedAt, format: .dateTime.day().month().hour().minute())")
                                    .font(SpaceTypography.label)
                            }
                        }
                    }
                }
                if let address = text(info.location?.address) {
                    SpaceCard("Address") {
                        Text(address)
                            .textSelection(.enabled)
                    }
                }

                if let hint = text(info.location?.hint) {
                    SpaceCard("Access") {
                        Text(hint)
                            .textSelection(.enabled)
                    }
                }

                let contacts = SpaceDetailLink.contacts(for: info.contact)
                if !contacts.isEmpty {
                    SpaceCard("Contacts") {
                        linkRows(contacts)
                    }
                }

                ForEach(Array(keymasters.enumerated()), id: \.offset) { _, keymaster in
                    SpaceCard("Keyholder") {
                        if let name = text(keymaster.name) {
                            Text(name)
                                .font(SpaceTypography.body.weight(.semibold))
                        }
                        if let nickname = text(keymaster.ircNick) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("IRC nickname")
                                    .font(SpaceTypography.label)
                                    .foregroundStyle(palette.secondaryText)
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
                    SpaceCard("Feeds") {
                        linkRows(feeds)
                    }
                }

                if let website = info.website {
                    SpaceCard("Website") {
                        SpaceDetailLinkRow(link: SpaceDetailLink(
                            id: "website", title: "Website", value: website.absoluteString,
                            destination: website, symbolName: "safari"
                        ), palette: palette)
                    }
                }
            }
            .font(SpaceTypography.body)
            .foregroundStyle(palette.text)
            .frame(maxWidth: SpaceLayout.readableWidth, alignment: .leading)
            .padding(SpaceLayout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(palette.background)
        .navigationTitle(info.name)
    }

    @ViewBuilder
    private func linkRows(_ links: [SpaceDetailLink]) -> some View {
        ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
            if index > 0 {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            SpaceDetailLinkRow(link: link, palette: palette)
        }
    }

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

private struct SpaceDetailLinkRow: View {
    var link: SpaceDetailLink
    var palette: SpacePalette

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
        HStack(alignment: .top, spacing: SpaceLayout.rowSpacing) {
            Image(systemName: link.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(link.title)
                    .font(SpaceTypography.label)
                    .foregroundStyle(palette.secondaryText)
                Text(link.value)
                    .font(SpaceTypography.body.weight(.medium))
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
        .frame(minHeight: SpaceLayout.minimumControlHeight)
        .contentShape(Rectangle())
    }
}
