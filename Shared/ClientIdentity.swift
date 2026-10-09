import Foundation

/// How the apps identify themselves to SpacePush, for its usage statistics:
/// a user agent such as `SpaceState/2.0.0 (iOS 26.0)` and, from the apps only,
/// a random install ID. The ID is created on first launch, tied to nothing
/// else, and goes away when the app is deleted. Widgets send no ID, since
/// they have their own storage and would count as separate installs.
enum ClientIdentity {
    static var headers: [String: String] {
        var headers = ["User-Agent": userAgent]
        if !isWidget {
            headers["X-SpaceState-Install"] = installID
        }
        return headers
    }

    /// `"ios"` or `"macos"`, sent with the push registration.
    static var platform: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }

    private static let installIDKey = "installID"

    private static var installID: String {
        if let id = UserDefaults.standard.string(forKey: installIDKey) {
            return id
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: installIDKey)
        return id
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
