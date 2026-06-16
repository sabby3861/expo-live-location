import Foundation

/// A circular geographic area worth alerting on — the traveller-safety primitive
/// the risk layer is built around.
///
/// A zone is a center coordinate, a radius in meters, and a human-readable name.
/// Like `LocationSample`, it is a framework-free `Sendable` value type: it carries
/// no CoreLocation types, so it can be constructed in tests and crossed between
/// concurrency domains freely. The geodesic math that relates a sample to a zone
/// lives in `proximity(to:)`, which delegates to CoreLocation in the one file
/// allowed to import it.
public struct RiskZone: Sendable, Equatable {

    /// A short, human-readable label for the zone (e.g. "Harbor District").
    /// Used as the alert's identity when it surfaces to the UI.
    public let name: String

    /// The center of the zone, in WGS-84 degrees.
    public let center: LocationSample.Coordinate

    /// The zone's radius in meters. A sample is "inside" the zone when its
    /// distance to `center` is no greater than this value.
    public let radius: Double

    /// Creates a risk zone.
    ///
    /// - Parameters:
    ///   - name: A short label identifying the zone to the user.
    ///   - center: The geographic center of the zone.
    ///   - radius: The zone radius in meters. Callers are responsible for passing
    ///     a positive, finite value; the boundary checks treat a non-positive
    ///     radius as a zone that can never be entered.
    public init(name: String, center: LocationSample.Coordinate, radius: Double) {
        self.name = name
        self.center = center
        self.radius = radius
    }
}

extension LocationSample {
    /// The straight-line distance, in meters, from this sample to the center of
    /// `zone`.
    ///
    /// This is a distance to the zone's *center*, not to its boundary — compare
    /// the result against `zone.radius` to decide containment. The computation is
    /// a great-circle distance performed by CoreLocation (see
    /// `Coordinate.distance(to:)`), so it matches the device's own geometry.
    public func proximity(to zone: RiskZone) -> Double {
        coordinate.distance(to: zone.center)
    }
}
