import Foundation

/// Where the apps keep their settings. Debug builds launched by the UI tests with
/// `-UITestFixtures` use a separate settings suite that starts empty on every launch,
/// so tests never read or change the real preferences of an installed app.
nonisolated enum AppEnvironment {
    #if DEBUG
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-UITestFixtures")
    #else
    static let isUITest = false
    #endif

    /// UserDefaults is documented as thread-safe; the reference itself never changes.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        #if DEBUG
        if isUITest { return UITestFixtures.makeDefaults() }
        #endif
        return .standard
    }()
}
