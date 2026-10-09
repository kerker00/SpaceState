import Foundation
import SpacePushClient

extension StatusService {
    /// SpacePush at `SpacePushURL` from the Info.plist, with direct reads as fallback.
    static var configured: StatusService {
        StatusService(spacePush: configuredServiceURL.map(SpacePushClient.configured))
    }

    /// `SpacePushURL` from the Info.plist, set per build configuration with `SPACEPUSH_URL`.
    static var configuredServiceURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SpacePushURL") as? String).flatMap(URL.init(string:))
    }
}

extension SpacePushClient {
    /// A client that identifies the app or widget to SpacePush (see `ClientIdentity`).
    static func configured(baseURL: URL) -> SpacePushClient {
        SpacePushClient(baseURL: baseURL, headers: ClientIdentity.headers, activePeriods: ClientIdentity.activePeriods)
    }
}
