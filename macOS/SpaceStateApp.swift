import SwiftUI

@main
struct SpaceStateApp: App {
    @State private var store: StatusStore
    @State private var directory = DirectoryStore()

    init() {
        let store = StatusStore()
        store.startPolling()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(store: store)
        } label: {
            Label {
                Text(store.status.title)
            } icon: {
                Image(systemName: store.status.symbolName)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, directory: directory)
        }
    }
}
