import Foundation
import SpacePushClient

extension StatusService {
    /// SpacePush at `SpacePushURL` from the Info.plist, with direct reads as fallback.
    static var configured: StatusService {
        StatusService(spacePush: PushStore.configuredServiceURL.map { SpacePushClient(baseURL: $0) })
    }
}
