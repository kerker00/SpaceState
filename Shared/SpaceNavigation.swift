import Foundation
import Observation

/// One temporary target; the persistent main selection and push preferences stay separate.
@MainActor
@Observable
final class SpaceNavigation {
    struct Destination: Identifiable {
        let id = UUID()
        let target: SpaceDestination
        let store: StatusStore
    }

    private(set) var destination: Destination?
    @ObservationIgnored private let makeStore: (URL) -> StatusStore

    init(makeStore: @escaping (URL) -> StatusStore = { StatusStore(selection: .temporary($0)) }) {
        self.makeStore = makeStore
    }

    func open(_ target: SpaceDestination) {
        destination?.store.pausePolling()
        destination = Destination(target: target, store: makeStore(target.endpoint))
    }

    @discardableResult
    func open(url: URL) -> Bool {
        guard let target = SpaceDestination(url: url) else { return false }
        open(target)
        return true
    }

    func close() {
        destination?.store.pausePolling()
        destination = nil
    }

    func resume() { destination?.store.resumePolling() }
    func pause() { destination?.store.pausePolling() }
}
