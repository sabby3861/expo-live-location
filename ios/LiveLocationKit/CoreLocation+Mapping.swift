@preconcurrency import CoreLocation

/// Translations between CoreLocation's types and the library's domain types.
///
/// CoreLocation is imported in exactly two files — this one and
/// `SystemLocationSource` — so the rest of the package stays framework-free and
/// the mapping logic has a single, reviewable home.
extension LocationSample {
    /// Projects a `CLLocation` into the framework-free domain value.
    init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            altitude: location.altitude,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }
}

extension LocationAuthorizationStatus {
    /// Maps a CoreLocation authorization status to the domain enum.
    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedAlways: self = .authorizedAlways
        case .authorizedWhenInUse: self = .authorizedWhenInUse
        @unknown default: self = .denied
        }
    }
}

extension LocationError {
    /// Maps an error reported by CoreLocation to the domain error set, defaulting
    /// to `.locationUnavailable` for anything that is not an explicit denial.
    init(_ error: Error) {
        guard let clError = error as? CLError else {
            self = .locationUnavailable
            return
        }
        switch clError.code {
        case .denied: self = .denied
        default: self = .locationUnavailable
        }
    }
}
