import CoreLocation
import Foundation
import Observation

/// Created only for an explicit location action. One fix, no background updates,
/// and no saved coordinates. Cancellation invalidates late delegate callbacks.
@MainActor
@Observable
final class OnboardingLocation: NSObject, CLLocationManagerDelegate {
    private(set) var isRequesting = false
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var result: ((CLLocation?) -> Void)?
    @ObservationIgnored private var requestedAuthorization = false

    func request(result: @escaping (CLLocation?) -> Void) {
        cancel()
        isRequesting = true
        self.result = result
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        authorize(manager)
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        result = nil
        requestedAuthorization = false
        isRequesting = false
    }

    private func finish(_ location: CLLocation?) {
        let reply = result
        cancel()
        reply?(location)
    }

    private func authorize(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            guard !requestedAuthorization else { return }
            requestedAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard timeout == nil else { return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                self?.finish(nil)
            }
            manager.requestLocation()
        default:
            finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        authorize(manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager else { return }
        let location = locations.last {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy.isFinite &&
                abs($0.timestamp.timeIntervalSinceNow) <= 60 && CLLocationCoordinate2DIsValid($0.coordinate)
        }
        finish(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard manager === self.manager else { return }
        finish(nil)
    }
}
