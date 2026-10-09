import SwiftUI

extension PushStore.Status {
    /// A line for the settings that explains the notification state; nil while turned off.
    var message: LocalizedStringKey? {
        switch self {
        case .off: nil
        case .denied: "Notifications are turned off in System Settings."
        case .registering: "Registering…"
        case .registered: "You will be notified about the selected space."
        case .failed(let message): "Registration failed: \(message)"
        }
    }
}
