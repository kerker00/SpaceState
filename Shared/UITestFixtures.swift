#if DEBUG
import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient

/// Fixed sample data for UI tests: no network, no SpacePush, no real spaces.
/// Launch arguments choose the starting point:
/// - `-UITestOnboarded`: Mainframe is already selected and the first run is done.
/// - `-UITestPushEnabled`: notifications were turned on before.
/// - `-UITestPushDenied`: the system refuses notifications.
nonisolated enum UITestFixtures {
    static let suiteName = "net.grafixmafia.spacestate.uitests"

    static func has(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if has("-UITestOnboarded") {
            defaults.set(Mainframe.spaceAPIEndpoint.absoluteString, forKey: "spaceEndpoint")
            defaults.set("Mainframe", forKey: "onboardingSpaceName")
            defaults.set(true, forKey: "onboardingStarted")
            defaults.set(true, forKey: "onboardingSpaceConfirmed")
            defaults.set(true, forKey: "onboardingComplete")
        }
        if has("-UITestPushEnabled") { defaults.set(true, forKey: "pushEnabled") }
        return defaults
    }

    static var service: StatusService {
        StatusService(spacePush: nil, direct: StatusClient(load: { request in try respond(to: request) }))
    }

    private static let leineLab = URL(string: "https://leinelab.example/spaceapi.json")!
    private static let chaosdorf = URL(string: "https://chaosdorf.example/spaceapi.json")!
    private static let devTal = URL(string: "https://devtal.example/spaceapi.json")!


    static func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let body: String
        switch url {
        case SpaceDirectory.aggregatorURL: body = directory
        case Mainframe.spaceAPIEndpoint: body = mainframe
        case Mainframe.openStateURL: body = rooms
        case leineLab: body = space("LeineLab", open: false, address: "Beispielstraße 5, 30159 Hannover", message: "See you at the next meetup!")
        case chaosdorf: body = space("Chaosdorf", open: true, address: "Sonnenstraße 58, 40227 Düsseldorf", message: nil)
        default: throw URLError(.cannotFindHost)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }

    private static var now: Int { Int(Date().timeIntervalSince1970) }

    private static var directory: String {
        let entries = [
            (Mainframe.spaceAPIEndpoint, mainframe),
            (chaosdorf, space("Chaosdorf", open: true, address: "Sonnenstraße 58, 40227 Düsseldorf", message: nil)),
            (leineLab, space("LeineLab", open: false, address: "Beispielstraße 5, 30159 Hannover", message: nil)),
            (devTal, #"{"api_compatibility":["14"],"space":"/dev/tal","state":{}}"#)
        ]
        return "[" + entries.map { #"{"url":"\#($0.0.absoluteString)","lastSeen":\#(now),"data":\#($0.1)}"# }
            .joined(separator: ",") + "]"
    }

    private static func space(_ name: String, open: Bool, address: String, message: String?) -> String {
        let message = message.map { #","message":"\#($0)""# } ?? ""
        return #"{"api_compatibility":["14"],"space":"\#(name)","location":{"address":"\#(address)"},"state":{"open":\#(open),"lastchange":\#(now - 7200)\#(message)},"sensors":{"people_now_present":[{"value":0}]}}"#
    }

    private static var mainframe: String {
        #"""
        {"api_compatibility":["14"],"space":"Mainframe","url":"https://mainframe.example",
         "location":{"address":"Bahnhofsplatz 10, 26122 Oldenburg","lat":53.1435,"lon":8.2146,"hint":"Ring the hackspace bell."},
         "state":{"open":true,"lastchange":\#(now - 7200),"message":"Welcome to the hackerspace!"},
         "contact":{"email":"info@mainframe.example","matrix":"#mainframe:matrix.example","mastodon":"@mainframe@social.example"},
         "sensors":{"people_now_present":[{"value":7}],
                    "temperature":[{"value":21.5,"unit":"°C","location":"Hackspace"}],
                    "humidity":[{"value":48,"unit":"%","location":"Hackspace"}],
                    "carbondioxide":[{"value":620,"unit":"ppm","location":"Hackspace"}]},
         "feeds":{"blog":{"url":"https://mainframe.example/blog.rss","type":"rss"}},
         "projects":["https://mainframe.example/projects"]}
        """#
    }

    private static var rooms: String {
        #"{"space":{"state":"open+","timestamp":\#(now - 3600)},"radstelle":{"state":"member","timestamp":\#(now - 3600)},"lab3d":{"state":"closed","timestamp":\#(now - 3600)}}"#
    }
}
#endif
