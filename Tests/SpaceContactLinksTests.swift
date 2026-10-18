import Foundation
import SpaceAPI
import Testing

/// Contact and feed values come from space operators; only well-formed values get an action.
@Suite
struct SpaceContactLinksTests {
    private func destination(_ contact: SpaceInfo.Contact) -> String? {
        SpaceDetailLink.contacts(for: contact).first?.destination?.absoluteString
    }

    @Test func contactsKeepAFixedOrderAndSkipEmptyValues() {
        let contact = SpaceInfo.Contact(
            email: "info@example.org", phone: "+49 441 1", irc: "ircs://irc.example.org/#space",
            mailingList: "  ", matrix: "#space:example.org", mastodon: "@space@social.example",
            xmpp: "space@xmpp.example.org", mumble: "mumble://voice.example.org", sip: "sip:100@pbx.example.org",
            issueMail: "noc@example.org", gopher: "gopher://gopher.example.org"
        )
        let rows = SpaceDetailLink.contacts(for: contact)
        #expect(rows.map(\.id) == ["contact-email", "contact-phone", "contact-irc", "contact-matrix", "contact-mastodon",
                                   "contact-xmpp", "contact-mumble", "contact-sip", "contact-issue-mail", "contact-gopher"])
        #expect(rows.allSatisfy { $0.destination != nil })
        #expect(SpaceDetailLink.contacts(for: .init()).isEmpty)
    }

    @Test func valuesAreTrimmedForDisplay() throws {
        let row = try #require(SpaceDetailLink.contacts(for: .init(email: "  info@example.org\n")).first)
        #expect(row.value == "info@example.org")
        #expect(row.symbolName == "envelope")
    }

    @Test(arguments: [
        ("info@example.org", "mailto:info@example.org"),
        ("mailto:Info@Example.org", "mailto:Info@Example.org"),
        ("MAILTO:a@b.example", "mailto:a@b.example")
    ])
    func emailAddressesBecomeMailLinks(value: String, expected: String) {
        #expect(destination(.init(email: value)) == expected)
    }

    @Test(arguments: ["no-at-sign", "a@b@c.example", "a b@c.example", "a@b.example/path", "@example.org", "a@", "a@b?subject=x"])
    func malformedEmailAddressesHaveNoAction(value: String) {
        #expect(destination(.init(email: value)) == nil)
    }

    @Test(arguments: [
        ("+49 (441) 123-45.6", "tel:+49441123456"),
        ("tel:0441 1", "tel:04411"),
        ("0441", "tel:0441")
    ])
    func phoneNumbersDropFormatting(value: String, expected: String) {
        #expect(destination(.init(phone: value)) == expected)
    }

    @Test(arguments: ["call us", "+", "0441 ext. 5", "++49"])
    func phoneValuesWithoutDigitsOnlyHaveNoAction(value: String) {
        #expect(destination(.init(phone: value)) == nil)
    }

    @Test func hostedChatLinksAcceptOnlyTheirSchemes() {
        #expect(destination(.init(irc: "irc://irc.example.org/#space")) == "irc://irc.example.org/#space")
        #expect(destination(.init(irc: "https://webchat.example.org/")) == "https://webchat.example.org/")
        #expect(destination(.init(irc: "irc.example.org")) == nil)
        #expect(destination(.init(irc: "ftp://irc.example.org")) == nil)
        #expect(destination(.init(irc: "irc:///no-host")) == nil)
        #expect(destination(.init(mumble: "mumble://voice.example.org:64738")) == "mumble://voice.example.org:64738")
        #expect(destination(.init(mumble: "ts3server://voice.example.org")) == nil)
        #expect(destination(.init(gopher: "gopher://gopher.example.org/1")) == "gopher://gopher.example.org/1")
        #expect(destination(.init(gopher: "javascript:alert(1)")) == nil)
    }

    @Test func controlCharactersBlockHostedLinks() {
        #expect(destination(.init(irc: "https://chat.example.org/\u{7}")) == nil)
    }

    @Test func mailingListsAcceptWebPagesOrAddresses() {
        #expect(destination(.init(mailingList: "https://lists.example.org/space")) == "https://lists.example.org/space")
        #expect(destination(.init(mailingList: "space@lists.example.org")) == "mailto:space@lists.example.org")
        #expect(destination(.init(mailingList: "space list")) == nil)
    }

    @Test func matrixIdentifiersOpenMatrixTo() {
        #expect(destination(.init(matrix: "#space:example.org")) == "https://matrix.to/#/%23space:example.org")
        #expect(destination(.init(matrix: "@user:example.org")) == "https://matrix.to/#/%40user:example.org")
        #expect(destination(.init(matrix: "!room:example.org")) == "https://matrix.to/#/%21room:example.org")
        #expect(destination(.init(matrix: "https://matrix.to/#/%23space:example.org")) == "https://matrix.to/#/%23space:example.org")
    }

    @Test(arguments: ["space:example.org", "#nocolon", "#:example.org", "#space:", "#space name:example.org"])
    func malformedMatrixIdentifiersHaveNoAction(value: String) {
        #expect(destination(.init(matrix: value)) == nil)
    }

    @Test func mastodonHandlesOpenTheProfile() {
        #expect(destination(.init(mastodon: "@space@social.example")) == "https://social.example/@space")
        #expect(destination(.init(mastodon: "space@social.example")) == "https://social.example/@space")
        #expect(destination(.init(mastodon: "https://social.example/@space")) == "https://social.example/@space")
    }

    @Test(arguments: ["@space", "@a@b@c.example", "@sp ace@social.example", "@space@.social.example", "@space@social.example.", "@space@soc/ial"])
    func malformedMastodonHandlesHaveNoAction(value: String) {
        #expect(destination(.init(mastodon: value)) == nil)
    }

    @Test func xmppAndSIPAddresses() {
        #expect(destination(.init(xmpp: "xmpp:room@conference.example.org")) == "xmpp:room@conference.example.org")
        #expect(destination(.init(xmpp: "room@conference.example.org")) == "xmpp:room@conference.example.org")
        #expect(destination(.init(xmpp: "room")) == nil)
        #expect(destination(.init(sip: "sip:+49 441 1")) == "sip:+494411")
        #expect(destination(.init(sip: "SIP:alice@pbx.example.org")) == "sip:alice@pbx.example.org")
        #expect(destination(.init(sip: "sips:alice@pbx.example.org")) == "sips:alice@pbx.example.org")
        #expect(destination(.init(sip: "100")) == "sip:100")
        #expect(destination(.init(sip: "sip:not an address")) == nil)
    }

    @Test func feedsKeepOrderAndOnlyOpenWebLinks() {
        let feeds = SpaceInfo.Feeds(
            blog: .init(url: URL(string: "https://example.org/blog.rss")!, type: "rss"),
            wiki: .init(url: URL(string: "https://wiki.example.org")!),
            calendar: .init(url: URL(string: "webcal://example.org/events.ics")!, type: "ical"),
            flickr: .init(url: URL(string: "http://flickr.example/space")!)
        )
        let rows = SpaceDetailLink.feeds(for: feeds)
        #expect(rows.map(\.id) == ["feed-blog", "feed-wiki", "feed-calendar", "feed-flickr"])
        #expect(rows.map(\.value) == ["https://example.org/blog.rss", "https://wiki.example.org", "webcal://example.org/events.ics", "http://flickr.example/space"])
        #expect(rows.map { $0.destination?.absoluteString } == ["https://example.org/blog.rss", "https://wiki.example.org", nil, "http://flickr.example/space"])
        #expect(SpaceDetailLink.feeds(for: .init()).isEmpty)
    }
}
