import Foundation
import SpacePushClient

extension StatusService {
    /// SpacePush at `SpacePushURL` from the Info.plist, with direct reads as fallback.
    static var configured: StatusService {
        StatusService(spacePush: configuredServiceURL.map { SpacePushClient(baseURL: $0) })
    }

    /// `SpacePushURL` from the Info.plist, set per build configuration with `SPACEPUSH_URL`.
    static var configuredServiceURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SpacePushURL") as? String).flatMap(URL.init(string:))
    }
}
