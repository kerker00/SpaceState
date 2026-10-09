import AppKit

/// Whether the app shows a Dock icon. It starts as a menu bar app (LSUIElement)
/// and switches to a regular app when the user turns the Dock icon on.
enum DockIcon {
    static let defaultsKey = "showDockIcon"

    static var isVisible: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func apply(visible: Bool) {
        NSApplication.shared.setActivationPolicy(visible ? .regular : .accessory)
        // Hiding the Dock icon deactivates the app; keep the open window in front.
        NSApplication.shared.activate()
    }
}
