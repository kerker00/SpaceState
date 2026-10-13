import Foundation
import MainframeStatus
import Observation
import SpaceAPI
import SpacePushClient
import WidgetKit

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

    static let refreshIntervals: [Duration] = [.seconds(60), .seconds(120), .seconds(300), .seconds(600), .seconds(900)]

    private let service: StatusService
    private let defaults: UserDefaults
    private var pollTask: Task<Void, Never>?
    /// Desired room subscriptions survive failed/partial reads and cold starts.
    private var pushRoomIDs: Set<String>
    private let reloadWidgets: () -> Void

    private enum Keys {
        static let endpoint = "spaceEndpoint"
        static let refreshSeconds = "refreshSeconds"
        static let pushRoomIDs = "mainframePushRoomIDs"
    }

    init(
        service: StatusService = .configured, defaults: UserDefaults = .standard,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.service = service
        self.defaults = defaults
        self.reloadWidgets = reloadWidgets
        pushRoomIDs = Self.validRoomIDs(defaults.stringArray(forKey: Keys.pushRoomIDs) ?? [])
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
            async let info = service.space(at: endpoint)
            // The rooms are extra detail; failing to load them must not hide the space's state.
            let rooms = Mainframe.isMainframe(endpoint) ? (try? await service.mainframeRooms()) ?? [] : []
            let fetchedInfo = try await info
            guard endpoint == self.endpoint else { return }
            // Widgets refresh only a few times an hour; tell them when the app sees a change.
            if fetchedInfo.status != self.info?.status || rooms.map(\.state) != self.rooms.map(\.state) {
                reloadWidgets()
            }
            self.info = fetchedInfo
            self.rooms = rooms
            if Mainframe.isMainframe(endpoint) {
                let newIDs = Self.validRoomIDs(rooms.map(\.id)).subtracting(pushRoomIDs)
                pushRoomIDs.formUnion(newIDs.sorted().prefix(max(0, 49 - pushRoomIDs.count)))
                defaults.set(pushRoomIDs.sorted(), forKey: Keys.pushRoomIDs)
            }
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
            + (Mainframe.isMainframe(endpoint) ? pushRoomIDs.sorted().map {
                PushSubscription(endpoint: endpoint, room: $0)
            } : [])
    }

    private static func validRoomIDs(_ ids: [String]) -> Set<String> {
        let valid = Set(ids.filter {
            $0 != "space" && (1...32).contains($0.utf8.count) && $0.utf8.allSatisfy {
                (97...122).contains($0) || (48...57).contains($0) || $0 == 95
            }
        })
        // The device API accepts at most 50 subscriptions, including the space.
        return Set(valid.sorted().prefix(49))
    }
}
