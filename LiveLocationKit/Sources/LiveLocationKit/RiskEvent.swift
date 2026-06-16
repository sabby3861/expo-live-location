import Foundation

/// A boundary-crossing alert emitted by `RiskMonitor` when the device's relation
/// to a `RiskZone` changes.
///
/// Events fire only on transitions, never on every sample: a device sitting still
/// inside a zone produces one `.entered` and then silence until it leaves. Each
/// event carries the zone it concerns, the distance from the triggering sample to
/// that zone's center, and the sample itself, so a UI can render the alert with
/// full context without re-deriving anything.
public struct RiskEvent: Sendable, Equatable {

    /// The kind of boundary crossing an event represents.
    public enum Kind: String, Sendable, Equatable {
        /// The device moved inside the zone's radius.
        case entered
        /// The device moved back outside the zone's radius.
        case exited
        /// The device came within the monitor's approaching margin of the zone
        /// but is not yet inside it — an early, softer warning.
        case approaching
    }

    /// What happened at the boundary.
    public let kind: Kind

    /// The zone the crossing concerns.
    public let zone: RiskZone

    /// Distance in meters from the triggering sample to `zone.center`, matching
    /// `LocationSample.proximity(to:)`.
    public let distance: Double

    /// The location sample that triggered the event.
    public let sample: LocationSample

    /// Creates a risk event. Normally constructed by `RiskMonitor`; exposed for
    /// tests that assert on emitted events.
    public init(kind: Kind, zone: RiskZone, distance: Double, sample: LocationSample) {
        self.kind = kind
        self.zone = zone
        self.distance = distance
        self.sample = sample
    }
}
