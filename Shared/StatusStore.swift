import Foundation
import MainframeStatus
import Observation
import SpaceAPI
import SpacePushClient
import WidgetKit

/// Keeps the status of the selected space current and remembers the user's choices.
@MainActor
@Observable
final class StatusStore {
    private(set) var info: SpaceInfo?
    /// Only filled for Mainframe Oldenburg.
    private(set) var rooms: [MainframeRoom] = []
    /// Time of the last successful space refresh.
    private(set) var lastUpdate: Date?
    private(set) var lastAttempt: Date?
    private(set) var lastError: (any Error)?
    private(set) var isRefreshing = false

    var endpoint: URL {
        didSet {
            guard endpoint != oldValue else { return }
            defaults.set(endpoint.absoluteString, forKey: Keys.endpoint)
            info = nil
            rooms = []
            lastError = nil
            lastUpdate = nil
            lastAttempt = nil
            cancelRefresh()
            if pollingEnabled { startPolling() }
        }
    }

    var refreshInterval: Duration {
        didSet {
            guard refreshInterval != oldValue else { return }
            defaults.set(refreshInterval.components.seconds, forKey: Keys.refreshSeconds)
            if pollingEnabled { startPolling() }
        }
    }

    /// Unknown while the last fetch failed, so a stale state is never shown as current.
    var status: SpaceStatus {
        lastError == nil ? info?.status ?? .unknown : .unknown
    }

    static let refreshIntervals: [Duration] = [.seconds(60), .seconds(120), .seconds(300), .seconds(600), .seconds(900)]

    private let service: StatusService
    private let defaults: UserDefaults
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollingEnabled = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var refreshRevision = 0
    @ObservationIgnored private let waitForPoll: (Duration) async throws -> Void
    @ObservationIgnored private let now: () -> Date
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
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        waitForPoll: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.defaults = defaults
        self.reloadWidgets = reloadWidgets
        self.waitForPoll = waitForPoll
        self.now = now
        pushRoomIDs = Self.validRoomIDs(defaults.stringArray(forKey: Keys.pushRoomIDs) ?? [])
        endpoint = defaults.string(forKey: Keys.endpoint).flatMap(URL.init(string:)) ?? Mainframe.spaceAPIEndpoint
        let seconds = defaults.integer(forKey: Keys.refreshSeconds)
        refreshInterval = seconds > 0 ? .seconds(seconds) : .seconds(120)
    }

    func startPolling() {
        pollingEnabled = true
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard !Task.isCancelled, let interval = self?.refreshInterval, let wait = self?.waitForPoll else { return }
                do { try await wait(interval) } catch { return }
            }
        }
    }

    /// iOS resumes once on returning to the foreground; macOS keeps polling.
    func resumePolling() {
        guard !pollingEnabled else { return }
        startPolling()
    }

    func pausePolling() {
        pollingEnabled = false
        pollTask?.cancel()
        pollTask = nil
        cancelRefresh()
    }

    /// Notification handlers enqueue work and return promptly. The payload never
    /// changes the selection or supplies data to display. Widgets have their own selection.
    func notificationReceived(endpoint notifiedEndpoint: String?) {
        reloadWidgets()
        guard notifiedEndpoint == nil || notifiedEndpoint.flatMap(URL.init(string:)) == endpoint else { return }
        _ = requestRefresh()
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        await requestRefresh().value
    }

    /// One current worker per selection. New triggers coalesce to one follow-up
    /// fetch and invalidate the result that was already in progress.
    private func requestRefresh() -> Task<Void, Never> {
        refreshRevision += 1
        if let refreshTask { return refreshTask }
        let id = UUID()
        refreshID = id
        isRefreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(id: id)
        }
        refreshTask = task
        return task
    }

    private func cancelRefresh() {
        refreshRevision += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        isRefreshing = false
    }

    private func performRefresh(id: UUID) async {
        defer {
            if refreshID == id {
                refreshTask = nil
                refreshID = nil
                isRefreshing = false
            }
        }
        while !Task.isCancelled, refreshID == id {
            let revision = refreshRevision
            let endpoint = endpoint
            lastAttempt = now()
            do {
                async let info = service.space(at: endpoint)
                // Room failures affect detail display, not the desired push subscriptions.
                let rooms = Mainframe.isMainframe(endpoint) ? (try? await service.mainframeRooms()) ?? [] : []
                let fetchedInfo = try await info
                guard !Task.isCancelled, refreshID == id else { return }
                guard revision == refreshRevision, endpoint == self.endpoint else { continue }
                let previousStatus = status
                let previousRooms = self.rooms.map(\.state)
                self.info = fetchedInfo
                self.rooms = rooms
                if Mainframe.isMainframe(endpoint) {
                    let newIDs = Self.validRoomIDs(rooms.map(\.id)).subtracting(pushRoomIDs)
                    pushRoomIDs.formUnion(newIDs.sorted().prefix(max(0, 49 - pushRoomIDs.count)))
                    defaults.set(pushRoomIDs.sorted(), forKey: Keys.pushRoomIDs)
                }
                lastError = nil
                lastUpdate = now()
                if previousStatus != status || previousRooms != rooms.map(\.state) { reloadWidgets() }
            } catch is CancellationError {
                guard !Task.isCancelled, refreshID == id else { return }
            } catch {
                guard !Task.isCancelled, refreshID == id else { return }
                guard revision == refreshRevision, endpoint == self.endpoint else { continue }
                let previousStatus = status
                lastError = error
                if previousStatus != status { reloadWidgets() }
            }
            if revision == refreshRevision { return }
        }
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
