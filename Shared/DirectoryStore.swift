import Foundation
import Observation
import SpaceAPI

/// The list of spaces to choose from, loaded on demand from the SpaceAPI aggregator.
@Observable
final class DirectoryStore {
    private(set) var entries: [DirectoryEntry] = []
    private(set) var lastError: (any Error)?
    private(set) var isLoading = false

    private let client: StatusClient

    init(client: StatusClient = StatusClient()) {
        self.client = client
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await client.directory()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func entries(matching query: String) -> [DirectoryEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.info.name.localizedStandardContains(query)
                || ($0.info.location?.address?.localizedStandardContains(query) ?? false)
        }
    }
}
