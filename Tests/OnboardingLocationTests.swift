import CoreLocation
import Foundation
import Testing

/// Never asks the real system: the manager reports a chosen authorization and records requests.
nonisolated final class RecordingLocationManager: CLLocationManager {
    var status: CLAuthorizationStatus
    private(set) var authorizationRequests = 0
    private(set) var locationRequests = 0
    private(set) var stops = 0

    init(status: CLAuthorizationStatus) {
        self.status = status
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus { status }
    override func requestWhenInUseAuthorization() { authorizationRequests += 1 }
    override func requestLocation() { locationRequests += 1 }
    override func stopUpdatingLocation() { stops += 1 }
}

@Suite(.serialized)
@MainActor
struct OnboardingLocationTests {
    @MainActor
    final class Harness {
        var managers: [RecordingLocationManager] = []
        var status: CLAuthorizationStatus
        let timeout = ControlledRetry()
        var results: [CLLocation?] = []
        lazy var location = OnboardingLocation(
            makeManager: { [unowned self] in
                let manager = RecordingLocationManager(status: status)
                managers.append(manager)
                return manager
            },
            waitForTimeout: { [timeout] in try await timeout.sleep() }
        )

        init(status: CLAuthorizationStatus) { self.status = status }

        func request() { location.request { [weak self] in self?.results.append($0) } }
        var manager: RecordingLocationManager { managers.last! }
    }

    private func fix() -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 53.14, longitude: 8.21), altitude: 0,
                   horizontalAccuracy: 50, verticalAccuracy: -1, timestamp: Date())
    }

    @Test func undecidedPermissionIsAskedOnceThenALocationIsRequested() {
        let h = Harness(status: .notDetermined)
        h.request()
        #expect(h.location.isRequesting)
        #expect(h.manager.authorizationRequests == 1)
        #expect(h.manager.locationRequests == 0)
        h.location.locationManagerDidChangeAuthorization(h.manager)
        #expect(h.manager.authorizationRequests == 1)

        h.manager.status = .authorizedAlways
        h.location.locationManagerDidChangeAuthorization(h.manager)
        #expect(h.manager.locationRequests == 1)
        // A second authorization callback must not start another request or timeout.
        h.location.locationManagerDidChangeAuthorization(h.manager)
        #expect(h.manager.locationRequests == 1)

        let location = fix()
        h.location.locationManager(h.manager, didUpdateLocations: [location])
        #expect(h.results.count == 1)
        #expect(h.results.first! === location)
        #expect(!h.location.isRequesting)
        #expect(h.manager.delegate == nil)
        #expect(h.manager.stops == 1)
    }

    @Test(arguments: [CLAuthorizationStatus.denied, .restricted])
    func refusedPermissionFinishesWithoutALocation(status: CLAuthorizationStatus) {
        let h = Harness(status: status)
        h.request()
        #expect(h.results.count == 1)
        #expect(h.results.first! == nil)
        #expect(!h.location.isRequesting)
        #expect(h.manager.locationRequests == 0)
    }

    @Test func unusableFixesFinishWithoutALocation() {
        let h = Harness(status: .authorizedAlways)
        h.request()
        let stale = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1), altitude: 0,
                               horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date(timeIntervalSinceNow: -600))
        h.location.locationManager(h.manager, didUpdateLocations: [stale])
        #expect(h.results.count == 1)
        #expect(h.results.first! == nil)
    }

    @Test func failuresFinishWithoutALocation() {
        let h = Harness(status: .authorizedAlways)
        h.request()
        h.location.locationManager(h.manager, didFailWithError: CLError(.locationUnknown))
        #expect(h.results.count == 1)
        #expect(h.results.first! == nil)
    }

    @Test func timeoutFinishesWithoutALocation() async throws {
        let h = Harness(status: .authorizedAlways)
        h.request()
        try await eventually { h.timeout.count == 1 }
        h.timeout.fire()
        try await eventually { h.results.count == 1 }
        #expect(h.results.first! == nil)
        #expect(!h.location.isRequesting)
    }

    @Test func cancellingDropsTheResultAndLateCallbacks() async throws {
        let h = Harness(status: .authorizedAlways)
        h.request()
        try await eventually { h.timeout.count == 1 }
        let manager = h.manager
        h.location.cancel()
        #expect(!h.location.isRequesting)
        #expect(manager.delegate == nil)
        h.location.locationManager(manager, didUpdateLocations: [fix()])
        h.location.locationManager(manager, didFailWithError: CLError(.denied))
        try await eventually { h.timeout.count == 0 }
        #expect(h.results.isEmpty)
    }

    @Test func aNewRequestReplacesTheOldOne() {
        let h = Harness(status: .notDetermined)
        h.request()
        let first = h.manager
        h.request()
        #expect(h.managers.count == 2)
        #expect(first.delegate == nil)
        h.location.locationManager(first, didUpdateLocations: [fix()])
        #expect(h.results.isEmpty)
        #expect(h.location.isRequesting)
        #expect(h.manager.authorizationRequests == 1)
    }
}
