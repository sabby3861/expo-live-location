/// The app's authorization to use location services.
///
/// This mirrors CoreLocation's `CLAuthorizationStatus` but lives in the domain
/// layer so callers — including the test suite — never need to import
/// CoreLocation to reason about permission state. The mapping from the system
/// type is defined in `CoreLocation+Mapping.swift`.
public enum LocationAuthorizationStatus: Sendable, Equatable {
    /// The user has not yet chosen whether the app may use location services.
    case notDetermined
    /// The app is not authorized and the user cannot change this (e.g. parental
    /// controls or an MDM profile).
    case restricted
    /// The user explicitly denied location access for the app.
    case denied
    /// The app may use location services only while it is in use (foreground).
    case authorizedWhenInUse
    /// The app may use location services at any time.
    case authorizedAlways

    /// Whether this status permits the delivery of location updates.
    public var isAuthorized: Bool {
        switch self {
        case .authorizedWhenInUse, .authorizedAlways: true
        case .notDetermined, .restricted, .denied: false
        }
    }
}
