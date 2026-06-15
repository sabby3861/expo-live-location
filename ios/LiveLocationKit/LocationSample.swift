import Foundation

/// An immutable snapshot of the device's location at a single instant.
///
/// This is the currency of the whole library: every layer — the system source,
/// the public provider, and ultimately the Expo bridge — speaks in
/// `LocationSample` values. It is intentionally a plain `Sendable` value type
/// with no CoreLocation coupling so it can cross concurrency domains freely and
/// be constructed in tests without a device.
public struct LocationSample: Sendable, Equatable {

    /// A geographic coordinate in degrees (WGS-84), mirroring the meaning of
    /// `CLLocationCoordinate2D` without depending on CoreLocation.
    public struct Coordinate: Sendable, Equatable {
        /// Latitude in degrees. Positive values are north of the equator.
        public let latitude: Double
        /// Longitude in degrees. Positive values are east of the prime meridian.
        public let longitude: Double

        /// Creates a coordinate from latitude and longitude in degrees.
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// The geographic coordinate of the sample.
    public let coordinate: Coordinate

    /// Altitude in meters above sea level. Negative values indicate a position
    /// below sea level.
    public let altitude: Double

    /// Instantaneous speed in meters per second. Negative when the value is
    /// unavailable, matching CoreLocation's convention.
    public let speed: Double

    /// Radius of uncertainty for the coordinate, in meters. Negative when the
    /// coordinate is invalid, matching CoreLocation's convention.
    public let horizontalAccuracy: Double

    /// The moment the location was determined.
    public let timestamp: Date

    /// Creates a sample from its components. `speed` and `horizontalAccuracy`
    /// follow CoreLocation's convention where negative values mean "unavailable".
    public init(
        coordinate: Coordinate,
        altitude: Double,
        speed: Double,
        horizontalAccuracy: Double,
        timestamp: Date
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}
