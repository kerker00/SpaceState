import Foundation
import MainframeStatus
import Observation
import SpaceAPI
import SpacePushClient

/// Keeps the status of the selected space current and remembers the user's choices.
@Observable
final class StatusStore {
    private(set) var info: SpaceInfo?
    /// Only filled for Mainframe Oldenburg.
    private(set) var rooms: [MainframeRoom] = []
    private(set) var lastUpdate: Date?
    private(set) var lastError: (any Error)?
    private(set) var isRefreshing = false

    var endpoint: URL {
        didSet {
            guard endpoint != oldValue else { return }
            defaults.set(endpoint.absoluteString, forKey: Keys.endpoint)
            info = nil
            rooms = []
            lastError = nil
            startPolling()
        }
    }

    var refreshInterval: Duration {
        didSet {
            guard refreshInterval != oldValue else { return }
            defaults.set(refreshInterval.components.seconds, forKey: Keys.refreshSeconds)
            startPolling()
        }
    }

    /// Unknown while the last fetch failed, so a stale state is never shown as current.
    var status: SpaceStatus {
        lastError == nil ? info?.status ?? .unknown : .unknown
    }

    var isMainframe: Bool { Mainframe.isMainframe(endpoint) }

    static let refreshIntervals: [Duration] = [.seconds(60), .seconds(120), .seconds(300), .seconds(600), .seconds(900)]

    private let client: StatusClient
    private let defaults: UserDefaults
    private var pollTask: Task<Void, Never>?

    private enum Keys {
        static let endpoint = "spaceEndpoint"
        static let refreshSeconds = "refreshSeconds"
    }

    init(client: StatusClient = StatusClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        endpoint = defaults.string(forKey: Keys.endpoint).flatMap(URL.init(string:)) ?? Mainframe.spaceAPIEndpoint
        let seconds = defaults.integer(forKey: Keys.refreshSeconds)
        refreshInterval = seconds > 0 ? .seconds(seconds) : .seconds(120)
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        let endpoint = endpoint
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let info = client.space(at: endpoint)
            // The rooms are extra detail; failing to load them must not hide the space's state.
            let rooms = Mainframe.isMainframe(endpoint) ? (try? await client.mainframeRooms()) ?? [] : []
            let fetchedInfo = try await info
            guard endpoint == self.endpoint else { return }
            self.info = fetchedInfo
            self.rooms = rooms
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            guard endpoint == self.endpoint else { return }
            lastError = error
        }
        lastUpdate = .now
    }
}

extension StatusStore {
    /// What to be notified about: the selected space and, for Mainframe, each of its rooms.
    var pushSubscriptions: [PushSubscription] {
        [PushSubscription(endpoint: endpoint)]
            + rooms.filter { $0.id != "space" }.map { PushSubscription(endpoint: endpoint, room: $0.id) }
    }
}
