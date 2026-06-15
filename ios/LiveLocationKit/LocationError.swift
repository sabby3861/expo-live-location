import Foundation

/// The set of failures the library can surface to callers.
///
/// Errors are modeled as a small, closed enum rather than passing through
/// opaque `CLError` values: callers get an exhaustive, switchable set of
/// outcomes, and the CoreLocation dependency stays sealed inside the system
/// layer. The mapping from `CLError` lives in `CoreLocation+Mapping.swift`.
public enum LocationError: Error, Equatable {
    /// The user denied the app permission to use location services.
    case denied
    /// Location access is restricted and cannot be granted by the user.
    case restricted
    /// Authorization was granted but a location could not be produced — services
    /// are off, no signal is available, or the system reported a failure.
    case locationUnavailable
}

extension LocationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .denied:
            "Location access was denied. Enable it for this app in Settings."
        case .restricted:
            "Location access is restricted on this device and cannot be enabled."
        case .locationUnavailable:
            "A location could not be determined right now."
        }
    }
}
