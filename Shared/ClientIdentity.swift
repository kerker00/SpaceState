import Foundation
import SpacePushClient

/// How the apps describe themselves to SpacePush, for its usage statistics:
/// a user agent such as `SpaceState/2.0.0 (iOS 26.0)` and, from the apps only,
/// which day, week and month a request is the first of (see `ActivePeriods`).
/// No ID is sent. Widgets report no periods, since they have their own storage
/// and would count as separate installs.
enum ClientIdentity {
    static var headers: [String: String] {
        ["User-Agent": userAgent]
    }

    /// Shared by all clients, so concurrent requests report a period once.
    static let activePeriods: ActivePeriods? = {
        guard !isWidget else { return nil }
        // Earlier builds stored a random install ID; it is no longer sent.
        UserDefaults.standard.removeObject(forKey: "installID")
        return ActivePeriods.userDefaults()
    }()

    /// `"ios"` or `"macos"`, sent with the push registration.
    static var platform: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }

    private static var isWidget: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    private static var userAgent: String {
        let product = isWidget ? "SpaceStateWidget" : "SpaceState"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = os.patchVersion == 0
            ? "\(os.majorVersion).\(os.minorVersion)"
            : "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        #if os(macOS)
        let osName = "macOS"
        #else
        let osName = "iOS"
        #endif
        return "\(product)/\(version) (\(osName) \(osVersion))"
    }
}
