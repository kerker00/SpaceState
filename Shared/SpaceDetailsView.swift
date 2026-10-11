import SpaceAPI
import SwiftUI

/// Information a space publishes, shared by the phone app and the Mac's detail window.
struct SpaceDetailsView: View {
    var info: SpaceInfo

    var body: some View {
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
                    #if os(macOS)
                    .listRowBackground(Color(nsColor: .controlBackgroundColor))
                    #endif
                }
            }
        }
        .foregroundStyle(.primary)
        #if os(macOS)
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .listStyle(.insetGrouped)
        #endif
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
        #if os(macOS)
        .listRowBackground(Color(nsColor: .controlBackgroundColor))
        #endif
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
