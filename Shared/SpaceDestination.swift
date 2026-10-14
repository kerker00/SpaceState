import Foundation
import MainframeStatus
import SpaceAPI

/// Identity only. A link or notification can never supply a status to display.
nonisolated struct SpaceDestination: Equatable, Sendable {
    let endpoint: URL
    let room: String?

    init?(endpoint: String, room: String? = nil) {
        guard endpoint.utf8.count <= 8192, let url = try? SpaceEndpoint.parse(endpoint) else { return nil }
        let room = room == "space" ? nil : room
        if let room {
            guard Mainframe.isMainframe(url), (1...32).contains(room.utf8.count),
                  room.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else { return nil }
        }
        self.endpoint = url
        self.room = room
    }

    init?(url: URL) {
        guard url.absoluteString.utf8.count <= 32768, url.baseURL == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "spacestate", parts.host?.lowercased() == "status",
              parts.path.isEmpty, parts.user == nil, parts.password == nil, parts.port == nil,
              let encoded = parts.string, let hostRange = parts.rangeOfHost,
              encoded[hostRange.upperBound...].first == "?",
              parts.fragment == nil, let items = parts.queryItems,
              items.allSatisfy({ $0.name == "endpoint" || $0.name == "room" }),
              items.filter({ $0.name == "endpoint" }).count == 1,
              items.filter({ $0.name == "room" }).count <= 1,
              items.allSatisfy({ $0.value != nil }),
              let endpoint = items.first(where: { $0.name == "endpoint" })?.value else { return nil }
        self.init(endpoint: endpoint, room: items.first(where: { $0.name == "room" })?.value)
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = "spacestate"
        parts.host = "status"
        parts.queryItems = [URLQueryItem(name: "endpoint", value: endpoint.absoluteString)]
        if let room { parts.queryItems?.append(URLQueryItem(name: "room", value: room)) }
        // Fixed valid scheme/host and Foundation-encoded query items.
        return parts.url!
    }

    /// Older notifications without identity open the current primary space.
    static func notification(endpoint: String?, room: String?, fallback: URL) -> Self? {
        guard endpoint != nil || room == nil || room == "space" else { return nil }
        return Self(endpoint: endpoint ?? fallback.absoluteString, room: room)
    }
}
