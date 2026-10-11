import SpaceAPI
import SwiftUI

/// Information a space publishes, shared by the phone app and the Mac's detail window.
struct SpaceDetailsView: View {
    var info: SpaceInfo

    var body: some View {
        List {
            if let address = text(info.location?.address) {
                Section("Address") {
                    Text(address)
                        .textSelection(.enabled)
                }
            }

            if let hint = text(info.location?.hint) {
                Section("Access") {
                    Text(hint)
                        .textSelection(.enabled)
                }
            }

            let contacts = SpaceDetailLink.contacts(for: info.contact)
            if !contacts.isEmpty {
                Section("Contacts") {
                    ForEach(contacts) { link in
                        SpaceDetailLinkRow(link: link)
                    }
                }
            }

            ForEach(Array(keymasters.enumerated()), id: \.offset) { _, keymaster in
                Section("Keyholder") {
                    if let name = text(keymaster.name) {
                        Text(name)
                            .font(.headline)
                    }
                    if let nickname = text(keymaster.ircNick) {
                        LabeledContent("IRC nickname", value: nickname)
                            .textSelection(.enabled)
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
                Section("Feeds") {
                    ForEach(feeds) { link in
                        SpaceDetailLinkRow(link: link)
                    }
                }
            }

            if let website = info.website {
                Section {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                    }
                }
            }
        }
        .navigationTitle(info.name)
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

    var body: some View {
        if let destination = link.destination {
            Link(destination: destination) {
                label
            }
        } else {
            label
                .textSelection(.enabled)
        }
    }

    private var label: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                Text(link.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        } icon: {
            Image(systemName: link.symbolName)
        }
    }
}
