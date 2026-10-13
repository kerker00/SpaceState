import Foundation
import Observation
import SpaceAPI
import SpacePushClient

/// The list of spaces to choose from, loaded on demand through SpacePush or from the SpaceAPI aggregator.
@Observable
@MainActor
final class DirectoryStore {
    private(set) var entries: [DirectoryEntry] = []
    private(set) var lastError: (any Error)?
    private(set) var isLoading = false

    private let service: StatusService
    private let now: () -> Date
    @ObservationIgnored private let expiry: ObservationExpiry
    private var timings: [URL: ObservationTiming] = [:]
    private var freshnessRevision = 0

    init(service: StatusService = .configured, now: @escaping () -> Date = { Date() },
         waitForExpiry: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.service = service
        self.now = now
        expiry = ObservationExpiry(now: now, wait: waitForExpiry)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let observations = try await service.directoryObservations()
            try Task.checkCancellation()
            entries = observations.map(\.value)
            timings = Dictionary(observations.map { ($0.value.endpoint, $0.timing) }, uniquingKeysWith: { first, _ in first })
            lastError = nil
            expiry.schedule(Array(timings.values)) { [weak self] in self?.freshnessRevision += 1 }
        } catch is CancellationError {
            // A dismissed picker must not replace the previous result with an error.
        } catch {
            lastError = error
        }
    }

    func status(for entry: DirectoryEntry) -> SpaceStatus {
        _ = freshnessRevision
        guard lastError == nil, let timing = timings[entry.endpoint] else { return .unknown }
        return timing.currentStatus(entry.info.status, at: now())
    }

    func timing(for entry: DirectoryEntry) -> ObservationTiming? { timings[entry.endpoint] }

    func entries(matching query: String) -> [DirectoryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.info.name.localizedStandardContains(query)
                || ($0.info.location?.address?.localizedStandardContains(query) ?? false)
        }
    }
}
