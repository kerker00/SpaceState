import Foundation
import SpaceAPI
import SwiftUI

/// Shared external links and contact rows for the iOS and macOS detail views.
nonisolated struct SpaceDetailLink: Identifiable, Sendable {
    let id: String
    let title: LocalizedStringResource
    let value: String
    let destination: URL?
    let symbolName: String
    var description: String? = nil
    var name: String? = nil

    static func projects(for projects: [URL]) -> [SpaceDetailLink] {
        projects.enumerated().map { index, url in
            SpaceDetailLink(id: "project-\(index)", title: "Project", value: url.absoluteString,
                            destination: validatedWebURL(url), symbolName: "hammer")
        }
    }

    static func links(for links: [SpaceInfo.Link]) -> [SpaceDetailLink] {
        links.enumerated().map { index, link in
            SpaceDetailLink(id: "link-\(index)", title: "Link", value: link.url.absoluteString,
                destination: validatedWebURL(link.url), symbolName: "link",
                description: plainText(link.description), name: plainText(link.name))
        }
    }

    /// Provider names are plain text, never localization keys or Markdown.
    static func plainText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func validatedWebURL(_ url: URL) -> URL? {
        (try? SpaceEndpoint.validate(url)) != nil ? url : nil
    }

    static func contacts(for contact: SpaceInfo.Contact) -> [SpaceDetailLink] {
        [
            row("email", "Email", contact.email, "envelope", destination: mailURL),
            row("phone", "Phone", contact.phone, "phone", destination: phoneURL),
            row("irc", "IRC", contact.irc, "bubble.left.and.bubble.right", destination: {
                hostedURL($0, schemes: ["http", "https", "irc", "ircs"])
            }),
            row("mailing-list", "Mailing list", contact.mailingList, "envelope.badge", destination: {
                webURL($0) ?? mailURL($0)
            }),
            row("matrix", "Matrix", contact.matrix, "bubble.left.and.bubble.right", destination: matrixURL),
            row("mastodon", "Mastodon", contact.mastodon, "bubble.left", destination: mastodonURL),
            row("xmpp", "XMPP", contact.xmpp, "bubble.left.and.bubble.right", destination: {
                addressURL($0, scheme: "xmpp")
            }),
            row("mumble", "Mumble", contact.mumble, "headphones", destination: {
                hostedURL($0, schemes: ["http", "https", "mumble"])
            }),
            row("sip", "SIP", contact.sip, "phone.connection", destination: sipURL),
            row("issue-mail", "Report an issue", contact.issueMail, "exclamationmark.bubble", destination: mailURL),
            row("gopher", "Gopher", contact.gopher, "network", destination: {
                hostedURL($0, schemes: ["http", "https", "gopher"])
            })
        ].compactMap { $0 }
    }

    static func feeds(for feeds: SpaceInfo.Feeds) -> [SpaceDetailLink] {
        [
            feed("blog", "Blog", feeds.blog, "newspaper"),
            feed("wiki", "Wiki", feeds.wiki, "book"),
            feed("calendar", "Calendar", feeds.calendar, "calendar"),
            feed("flickr", "Flickr", feeds.flickr, "photo.on.rectangle")
        ].compactMap { $0 }
    }

    private static func row(
        _ id: String, _ title: LocalizedStringResource, _ rawValue: String?, _ symbolName: String,
        destination: (String) -> URL?
    ) -> SpaceDetailLink? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return SpaceDetailLink(
            id: "contact-\(id)", title: title, value: value,
            destination: destination(value), symbolName: symbolName
        )
    }

    private static func feed(
        _ id: String, _ title: LocalizedStringResource, _ feed: SpaceInfo.Feed?, _ symbolName: String
    ) -> SpaceDetailLink? {
        guard let feed else { return nil }
        let value = feed.url.absoluteString
        return SpaceDetailLink(
            id: "feed-\(id)", title: title, value: value,
            destination: webURL(value), symbolName: symbolName
        )
    }

    /// Each contact type supplies its own allowlist; other values remain readable text.
    private static func hostedURL(_ value: String, schemes: Set<String>) -> URL? {
        guard value.rangeOfCharacter(from: .controlCharacters) == nil,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return components.url
    }

    private static func webURL(_ value: String) -> URL? {
        hostedURL(value, schemes: ["http", "https"])
    }

    private static func mailURL(_ value: String) -> URL? {
        addressURL(value, scheme: "mailto")
    }

    /// Build the scheme ourselves and keep the address out of the query and fragment.
    private static func addressURL(_ value: String, scheme: String) -> URL? {
        let address = removingPrefix("\(scheme):", from: value)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }),
              address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              address.rangeOfCharacter(from: CharacterSet(charactersIn: ":/?#\\")) == nil else { return nil }
        return opaqueURL(scheme: scheme, value: address)
    }

    private static func phoneURL(_ value: String) -> URL? {
        guard let number = phoneNumber(removingPrefix("tel:", from: value)) else { return nil }
        return opaqueURL(scheme: "tel", value: number)
    }

    private static func phoneNumber(_ value: String) -> String? {
        let formatting = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()-."))
        let number = value.components(separatedBy: formatting).joined()
        let digits = number.hasPrefix("+") ? String(number.dropFirst()) : number
        guard !digits.isEmpty, digits.allSatisfy({ "0123456789".contains($0) }) else { return nil }
        return number
    }

    private static func sipURL(_ value: String) -> URL? {
        let scheme = value.lowercased().hasPrefix("sips:") ? "sips" : "sip"
        let address = removingPrefix("\(scheme):", from: value)
        if let number = phoneNumber(address) {
            return opaqueURL(scheme: scheme, value: number)
        }
        return addressURL(value, scheme: scheme)
    }

    private static func opaqueURL(scheme: String, value: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.path = value
        return components.url
    }

    private static func matrixURL(_ value: String) -> URL? {
        if let url = webURL(value) { return url }
        guard let prefix = value.first, ["#", "@", "!"].contains(String(prefix)),
              let colon = value.firstIndex(of: ":"), colon > value.index(after: value.startIndex),
              value.index(after: colon) < value.endIndex,
              value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            return nil
        }
        // Encode the identifier as one fragment component, including its leading # or @.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:")
        guard let identifier = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "matrix.to"
        components.path = "/"
        components.percentEncodedFragment = "/\(identifier)"
        return components.url
    }

    private static func mastodonURL(_ value: String) -> URL? {
        if let url = webURL(value) { return url }
        let handle = value.hasPrefix("@") ? String(value.dropFirst()) : value
        let parts = handle.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let username = String(parts[0])
        let host = String(parts[1])
        let usernameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard username.rangeOfCharacter(from: usernameCharacters.inverted) == nil,
              host.rangeOfCharacter(from: hostCharacters.inverted) == nil,
              !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/@\(username)"
        return components.url
    }

    private static func removingPrefix(_ prefix: String, from value: String) -> String {
        value.lowercased().hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }
}

/// An endpoint opens a temporary status view; a website remains an external link.
nonisolated struct SpaceLinkedSpace: Identifiable, Sendable {
    let id: String
    let endpoint: SpaceDetailLink?
    let target: SpaceDestination?
    let website: SpaceDetailLink?

    static func rows(for spaces: [SpaceInfo.LinkedSpace]) -> [Self] {
        spaces.enumerated().compactMap { index, space in
            guard space.endpoint != nil || space.website != nil else { return nil }
            let target = space.endpoint.flatMap { url in
                // Check the URL itself before using its string; a relative URL can have a base.
                SpaceDetailLink.validatedWebURL(url).flatMap { SpaceDestination(endpoint: $0.absoluteString) }
            }
            return Self(id: "linked-space-\(index)", endpoint: space.endpoint.map {
                SpaceDetailLink(id: "endpoint-\(index)", title: "Space status", value: $0.absoluteString,
                    destination: nil, symbolName: "network")
            }, target: target, website: space.website.map {
                SpaceDetailLink(id: "website-\(index)", title: "Website", value: $0.absoluteString,
                    destination: SpaceDetailLink.validatedWebURL($0), symbolName: "safari")
            })
        }
    }
}
