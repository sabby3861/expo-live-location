import ExpoModulesCore

// LiveLocationKit's sources are compiled into this pod target in place, so its
// public types are visible here without an import.

/// The bridge form of a `RiskZone` as supplied by JavaScript through
/// `setRiskZones`.
///
/// JavaScript is untrusted input, so this record is also where zones are
/// validated: `riskZone()` returns `nil` for anything that cannot describe a real
/// area (non-finite numbers, a non-positive radius, or out-of-range coordinates),
/// and the adapter drops those rather than feeding a degenerate zone into the
/// monitor.
struct RiskZoneRecord: Record {
    @Field var name: String = ""
    @Field var latitude: Double = 0
    @Field var longitude: Double = 0
    /// Radius in meters; must be positive and finite to be accepted.
    @Field var radius: Double = 0

    init() {}

    /// Converts the record into a domain `RiskZone`, or `nil` if the inputs do not
    /// describe a valid zone.
    func riskZone() -> RiskZone? {
        guard latitude.isFinite, longitude.isFinite, radius.isFinite,
              radius > 0,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        return RiskZone(
            name: name,
            center: LocationSample.Coordinate(latitude: latitude, longitude: longitude),
            radius: radius
        )
    }
}

/// The bridge representation of a `RiskEvent`, the payload of the `onRiskAlert`
/// event. Flattened so JavaScript can render an alert without reaching into nested
/// objects; it mirrors `LocationSampleRecord`'s timestamp convention.
struct RiskEventRecord: Record {
    /// The crossing kind: `"entered"`, `"exited"`, or `"approaching"`.
    @Field var kind: String = ""
    /// The name of the zone the alert concerns.
    @Field var zone: String = ""
    /// Distance in meters from the triggering sample to the zone center.
    @Field var distance: Double = 0
    /// Latitude of the triggering sample.
    @Field var latitude: Double = 0
    /// Longitude of the triggering sample.
    @Field var longitude: Double = 0
    /// Milliseconds since the Unix epoch, matching `LocationSampleRecord`.
    @Field var timestamp: Double = 0

    init() {}

    init(_ event: RiskEvent) {
        kind = event.kind.rawValue
        zone = event.zone.name
        distance = event.distance
        latitude = event.sample.coordinate.latitude
        longitude = event.sample.coordinate.longitude
        timestamp = event.sample.timestamp.timeIntervalSince1970 * 1000
    }
}
