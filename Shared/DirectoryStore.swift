import Foundation
import Observation
import SpaceAPI
import SpacePushClient

/// The list of spaces to choose from, loaded on demand through SpacePush or from the SpaceAPI aggregator.
@Observable
final class DirectoryStore {
    private(set) var entries: [DirectoryEntry] = []
    private(set) var lastError: (any Error)?
    private(set) var isLoading = false

    private let service: StatusService

    init(service: StatusService = .configured) {
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await service.directory()
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
