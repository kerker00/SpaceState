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
    enum Selection {
        case saved
        case temporary(URL)
    }
    private(set) var info: SpaceInfo?
    /// Only filled for Mainframe Oldenburg.
    private(set) var rooms: [MainframeRoom] = []
    /// Time of the last successful space refresh.
    private(set) var lastUpdate: Date?
    private(set) var lastAttempt: Date?
    private(set) var lastError: (any Error)?
    private(set) var observationTiming: ObservationTiming?
    private(set) var roomsTiming: ObservationTiming?
    private(set) var lastRoomsError: (any Error)?
    private(set) var lastRoomsUpdate: Date?
    private(set) var lastRoomsAttempt: Date?
    private var freshnessRevision = 0
    private(set) var isRefreshing = false

    var endpoint: URL {
        didSet {
            guard endpoint != oldValue else { return }
            if remembersPreferences { defaults.set(endpoint.absoluteString, forKey: Keys.endpoint) }
            info = nil
            rooms = []
            lastError = nil
            lastUpdate = nil
            lastAttempt = nil
            observationTiming = nil
            roomsTiming = nil
            lastRoomsError = nil
            lastRoomsUpdate = nil
            lastRoomsAttempt = nil
            expiry.cancel()
            cancelRefresh()
            if pollingEnabled { startPolling() }
        }
    }

    var refreshInterval: Duration {
        didSet {
            guard refreshInterval != oldValue else { return }
            if remembersPreferences { defaults.set(refreshInterval.components.seconds, forKey: Keys.refreshSeconds) }
            if pollingEnabled { startPolling() }
        }
    }

    /// Unknown while the last fetch failed, so a stale state is never shown as current.
    var status: SpaceStatus {
        _ = freshnessRevision
        guard lastError == nil, let info, let observationTiming else { return .unknown }
        return observationTiming.currentStatus(info.status, at: now())
    }

    var freshness: ObservationFreshness {
        _ = freshnessRevision
        return observationTiming?.freshness(at: now()) ?? .unknown
    }

    var displayRooms: [MainframeRoom] {
        _ = freshnessRevision
        return ObservationDisplay.rooms(rooms, timing: roomsTiming, failed: lastRoomsError != nil, at: now())
    }

    var roomsFreshness: ObservationFreshness {
        _ = freshnessRevision
        return roomsTiming?.freshness(at: now()) ?? .unknown
    }

    var widgetSensorValues: [WidgetSensorReading] {
        _ = freshnessRevision
        return SpaceSensorPresentation.widget(info: info, timing: observationTiming,
            failed: lastError != nil, at: now())
    }

    static let refreshIntervals: [Duration] = [.seconds(60), .seconds(120), .seconds(300), .seconds(600), .seconds(900)]

    private let service: StatusService
    private let defaults: UserDefaults
    private let remembersPreferences: Bool
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollingEnabled = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var refreshRevision = 0
    @ObservationIgnored private let waitForPoll: (Duration) async throws -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let expiry: ObservationExpiry
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
        waitForExpiry: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = { .now },
        selection: Selection = .saved
    ) {
        self.service = service
        self.defaults = defaults
        if case .saved = selection { remembersPreferences = true }
        else { remembersPreferences = false }
        self.reloadWidgets = remembersPreferences ? reloadWidgets : {}
        self.waitForPoll = waitForPoll
        self.now = now
        expiry = ObservationExpiry(now: now, wait: waitForExpiry)
        pushRoomIDs = remembersPreferences ? Self.validRoomIDs(defaults.stringArray(forKey: Keys.pushRoomIDs) ?? []) : []
        switch selection {
        case .saved:
            endpoint = defaults.string(forKey: Keys.endpoint).flatMap(URL.init(string:)) ?? Mainframe.spaceAPIEndpoint
        case .temporary(let endpoint):
            self.endpoint = endpoint
        }
        let seconds = defaults.integer(forKey: Keys.refreshSeconds)
        refreshInterval = seconds > 0 ? .seconds(seconds) : .seconds(120)
    }

    func startPolling() {
        pollingEnabled = true
        freshnessRevision += 1
        scheduleExpiry()
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
        expiry.cancel()
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
            let service = service
            async let spaceResult = Self.result { try await service.spaceObservation(at: endpoint) }
            let roomsResult: Result<StatusObservation<[MainframeRoom]>, any Error>?
            if Mainframe.isMainframe(endpoint) {
                lastRoomsAttempt = now()
                roomsResult = await Self.result { try await service.mainframeRoomsObservation() }
            } else {
                roomsResult = nil
            }
            let fetchedSpace = await spaceResult
            guard !Task.isCancelled, refreshID == id else { return }
            guard revision == refreshRevision, endpoint == self.endpoint else { continue }
            let previousStatus = status
            let previousRooms = displayRooms.map(\.state)
            let previousSensors = widgetSensorValues
            switch fetchedSpace {
            case .success(let observation):
                info = observation.value
                observationTiming = observation.timing
                lastError = nil
                lastUpdate = now()
            case .failure(let error):
                if !(error is CancellationError) { lastError = error }
            }
            switch roomsResult {
            case .success(let observation):
                rooms = observation.value
                roomsTiming = observation.timing
                lastRoomsError = nil
                lastRoomsUpdate = now()
                if remembersPreferences && Mainframe.isMainframe(endpoint) {
                    let newIDs = Self.validRoomIDs(rooms.map(\.id)).subtracting(pushRoomIDs)
                    pushRoomIDs.formUnion(newIDs.sorted().prefix(max(0, 49 - pushRoomIDs.count)))
                    defaults.set(pushRoomIDs.sorted(), forKey: Keys.pushRoomIDs)
                }
            case .failure(let error):
                // Preserve names and last known values; only display state loses
                // its current claim. Desired push rooms are unchanged.
                if !(error is CancellationError) { lastRoomsError = error }
            case nil:
                rooms = []
                roomsTiming = nil
                lastRoomsError = nil
            }
            scheduleExpiry()
            if previousStatus != status || previousRooms != displayRooms.map(\.state)
                || previousSensors != widgetSensorValues { reloadWidgets() }
            if revision == refreshRevision { return }
        }
    }

    private nonisolated static func result<Value: Sendable>(
        _ fetch: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do { return .success(try await fetch()) } catch { return .failure(error) }
    }

    private func scheduleExpiry() {
        expiry.schedule([observationTiming, roomsTiming].compactMap { $0 }) { [weak self] in
            guard let self else { return }
            self.freshnessRevision += 1
            self.reloadWidgets()
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
