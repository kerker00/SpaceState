import MainframeStatus
import SpaceAPI
import SwiftUI

extension SpaceStatus {
    var title: LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .closed: "Closed"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .open: "door.left.hand.open"
        case .closed: "door.left.hand.closed"
        case .unknown: "questionmark.square.dashed"
        }
    }

    var color: Color {
        switch self {
        case .open: .green
        case .closed: .red
        case .unknown: .secondary
        }
    }
}

extension MainframeRoomState {
    var title: LocalizedStringResource {
        switch self {
        case .closed: "Closed"
        case .keyholder: "Keyholders only"
        case .member: "Members only"
        case .open: "Open"
        case .openPlus: "Open+"
        case .closing: "Closing"
        case .unknown(let raw): "Unknown (\(raw))"
        }
    }

    var color: Color {
        switch self {
        case .open, .openPlus: .green
        case .keyholder, .member, .closing: .orange
        case .closed: .red
        case .unknown: .secondary
        }
    }
}

/// A small colored dot for status lists.
struct StatusDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

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
