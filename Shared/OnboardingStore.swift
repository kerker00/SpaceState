import CoreLocation
import Foundation
import Observation
import SpaceAPI

/// Persists progress, but never the device's location. Existing installations
/// keep their selection and notification preference without a new first run.
@MainActor
@Observable
final class OnboardingStore {
    enum Step { case space, notifications, complete }
    private(set) var step: Step
    private(set) var selectedName: String
    private(set) var isEnablingNotifications = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedName = defaults.string(forKey: "onboardingSpaceName") ?? ""
        if defaults.bool(forKey: "onboardingComplete") {
            step = .complete
        } else if defaults.bool(forKey: "onboardingSpaceConfirmed") {
            step = .notifications
        } else if !defaults.bool(forKey: "onboardingStarted") &&
                    ["spaceEndpoint", "pushEnabled", "refreshSeconds", "reportedPeriods", "installID"]
                        .contains(where: { defaults.object(forKey: $0) != nil }) {
            step = .complete
            defaults.set(true, forKey: "onboardingComplete")
        } else {
            step = .space
        }
        defaults.set(true, forKey: "onboardingStarted")
    }

    var hasSelectedSpace: Bool { step != .space }
    var isComplete: Bool { step == .complete }

    func select(_ entry: DirectoryEntry, in store: StatusStore) {
        guard step == .space else { return }
        selectedName = entry.info.name
        defaults.set(selectedName, forKey: "onboardingSpaceName")
        // Explicitly persist even when the chosen endpoint equals the legacy default.
        defaults.set(entry.endpoint.absoluteString, forKey: "spaceEndpoint")
        store.endpoint = entry.endpoint
        defaults.set(true, forKey: "onboardingSpaceConfirmed")
        step = .notifications
    }

    func finish() {
        guard step == .notifications else { return }
        defaults.set(true, forKey: "onboardingComplete")
        step = .complete
    }

    func enableNotifications(using push: PushStore, store: StatusStore) async {
        guard step == .notifications, !isEnablingNotifications else { return }
        isEnablingNotifications = true
        defer { isEnablingNotifications = false }
        push.update(subscriptions: store.pushSubscriptions)
        await push.setEnabled(true)
        finish()
    }

    func skipNotifications(using push: PushStore) async {
        guard step == .notifications, !isEnablingNotifications else { return }
        isEnablingNotifications = true
        defer { isEnablingNotifications = false }
        // A killed app may have saved the enable intent before its system prompt
        // returned. "Not now" must also turn that interrupted intent off.
        await push.setEnabled(false)
        finish()
    }

    /// Only provider coordinates already present in the directory are compared.
    /// No geocoding or location-bearing network request is needed.
    static func nearest(in entries: [DirectoryEntry], to location: CLLocation) -> DirectoryEntry? {
        guard CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
        return entries.compactMap { entry -> (DirectoryEntry, CLLocationDistance)? in
            guard let lat = entry.info.location?.latitude,
                  let lon = entry.info.location?.longitude,
                  lat.isFinite, lon.isFinite,
                  CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return nil }
            let distance = location.distance(from: CLLocation(latitude: lat, longitude: lon))
            guard distance.isFinite else { return nil }
            return (entry, distance)
        }.min { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.endpoint.absoluteString < rhs.0.endpoint.absoluteString : lhs.1 < rhs.1
        }?.0
    }
}
