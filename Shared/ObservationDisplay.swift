import Foundation
import MainframeStatus
import SpaceAPI

enum ObservationDisplay {
    static func rooms(_ rooms: [MainframeRoom], timing: ObservationTiming?, failed: Bool = false,
                      at date: Date) -> [MainframeRoom] {
        guard !failed, timing?.freshness(at: date) == .current else {
            return rooms.map { MainframeRoom(id: $0.id, state: .unknown(""), since: $0.since) }
        }
        return rooms
    }
}

/// An expiry updates observable display state even between polls. The identifier
/// prevents a cancelled timer for an old selection or response from publishing.
@MainActor
final class ObservationExpiry {
    private let now: () -> Date
    private let wait: (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var id: UUID?

    init(now: @escaping () -> Date, wait: @escaping (Duration) async throws -> Void) {
        self.now = now
        self.wait = wait
    }

    deinit { task?.cancel() }

    func cancel() {
        id = nil
        let oldTask = task
        task = nil
        oldTask?.cancel()
    }

    func schedule(_ timings: [ObservationTiming], changed: @escaping () -> Void) {
        cancel()
        let date = now()
        guard let expiry = timings.compactMap(\.expiresAt).filter({ $0 > date }).min() else { return }
        let identifier = UUID()
        id = identifier
        let wait = wait
        // Large configured limits cannot overflow Duration. Rechecking also
        // catches clock changes before a very distant expiry.
        let interval = expiry.timeIntervalSince(date)
        guard interval.isFinite, interval > 0 else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let currentDate = self?.now() ?? date
                guard let nextExpiry = timings.compactMap(\.expiresAt).filter({ $0 > currentDate }).min() else { return }
                let interval = nextExpiry.timeIntervalSince(currentDate)
                guard interval.isFinite, interval > 0 else { return }
                let delay = Duration.seconds(min(900, interval))
                do { try await wait(delay) } catch { return }
                guard !Task.isCancelled, let self, self.id == identifier else { return }
                changed()
            }
        }
    }
}
