import ExpoModulesCore
import LiveLocationKit

/// The bridge representation of a `LocationSample`.
///
/// This is the single place a domain value is reshaped for JavaScript: the pure
/// `LiveLocationKit` types never know about Expo, and Expo's `Record`/`Field`
/// machinery never leaks below this adapter. The same record feeds both the
/// `getCurrentLocation` return value and the `onLocationUpdate` event payload.
struct LocationSampleRecord: Record {
    @Field var latitude: Double = 0
    @Field var longitude: Double = 0
    @Field var altitude: Double = 0
    /// Meters per second; negative when unavailable (CoreLocation convention).
    @Field var speed: Double = 0
    @Field var horizontalAccuracy: Double = 0
    /// Milliseconds since the Unix epoch, the natural unit for JavaScript `Date`.
    @Field var timestamp: Double = 0

    init() {}

    init(_ sample: LocationSample) {
        latitude = sample.coordinate.latitude
        longitude = sample.coordinate.longitude
        altitude = sample.altitude
        speed = sample.speed
        horizontalAccuracy = sample.horizontalAccuracy
        timestamp = sample.timestamp.timeIntervalSince1970 * 1000
    }
}
