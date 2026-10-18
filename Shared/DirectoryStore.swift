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
    private var searchTextByEndpoint: [URL: String] = [:]
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
            let loaded = observations.map(\.value)
            // Indexing walks every entry by reflection; doing it on the main actor
            // kept the search field from accepting input for seconds.
            if loaded != entries {
                let index = await Self.searchIndex(for: loaded)
                try Task.checkCancellation()
                entries = loaded
                searchTextByEndpoint = index
            }
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
        let terms = query.split(whereSeparator: \.isWhitespace).map { Self.folded(String($0)) }
        guard !terms.isEmpty else { return entries }
        return entries.filter { entry in
            let text = searchTextByEndpoint[entry.endpoint] ?? Self.folded(entry.info.name)
            return terms.allSatisfy { text.contains($0) }
        }
    }

    /// Case-, diacritic- and width-insensitive form, computed once per indexed
    /// text so each keystroke only needs a plain substring check.
    private nonisolated static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    @concurrent
    private nonisolated static func searchIndex(for entries: [DirectoryEntry]) async -> [URL: String] {
        Dictionary(entries.map { entry in
            (entry.endpoint, folded(searchableValues(in: entry).joined(separator: "\n")))
        }, uniquingKeysWith: { $0 + "\n" + $1 })
    }

    /// Index the loaded values once, including hidden addresses and nested data.
    /// Traversing values keeps model/schema field names out of search results and
    /// includes newly supported fields without a second hand-maintained field list.
    private nonisolated static func searchableValues(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let url = value as? URL {
            let text = url.absoluteString
            return [text.removingPercentEncoding ?? text]
        }
        if let date = value as? Date { return [date.formatted(.iso8601)] }
        if let scalar = value as? any LosslessStringConvertible { return [scalar.description] }
        return Mirror(reflecting: value).children.flatMap { searchableValues(in: $0.value) }
    }
}
