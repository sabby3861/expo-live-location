import Foundation

/// Watches a stream of location samples against a fixed set of `RiskZone`s and
/// emits a `RiskEvent` each time the device crosses a zone boundary.
///
/// The monitor is a pure value type with no CoreLocation, Expo, or device
/// dependency: it is driven entirely by the `LocationSample`s it is fed, so its
/// full behavior is exercised in unit tests with scripted coordinates and a mock
/// source. It does the geometry through `LocationSample.proximity(to:)` and holds
/// only a small per-zone membership state.
///
/// Each zone is tracked through three nested levels keyed off distance to the
/// zone center:
/// - **inside** — distance ≤ `radius`
/// - **approaching** — `radius` < distance ≤ `radius + approachingMargin`
/// - **outside** — distance > `radius + approachingMargin`
///
/// Events fire only on the transitions that matter, so a stationary device emits
/// nothing after its first classification:
/// - crossing *into* `inside` → `.entered`
/// - crossing *out of* `inside` → `.exited`
/// - first step from `outside` into `approaching` → `.approaching`
///
/// Zones begin in `outside`, so a first fix already within a zone correctly fires
/// `.entered` (the traveller is already at risk).
public struct RiskMonitor: Sendable {

    /// The default approaching margin, in meters: how far beyond a zone's radius a
    /// device may be and still earn an early `.approaching` warning.
    public static let defaultApproachingMargin: Double = 250

    /// Where a sample sits relative to a single zone. Declared `Comparable` (by
    /// `rawValue`) so transitions can be expressed as "crossed into/out of inside".
    private enum Level: Int, Comparable {
        case outside
        case approaching
        case inside

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private let zones: [RiskZone]
    private let approachingMargin: Double

    /// One membership level per zone, index-aligned with `zones`. Mutated as
    /// samples arrive; this is the monitor's entire state.
    private var levels: [Level]

    /// Creates a monitor for a set of zones.
    ///
    /// - Parameters:
    ///   - zones: The zones to watch. May be empty, in which case the monitor is
    ///     inert and `evaluate(_:)` always returns no events.
    ///   - approachingMargin: How many meters beyond a zone's radius still counts
    ///     as "approaching". Defaults to `defaultApproachingMargin`. A value ≤ 0
    ///     disables `.approaching` warnings, leaving only `.entered`/`.exited`.
    public init(zones: [RiskZone], approachingMargin: Double = RiskMonitor.defaultApproachingMargin) {
        self.zones = zones
        self.approachingMargin = approachingMargin
        self.levels = Array(repeating: .outside, count: zones.count)
    }

    /// Feeds one sample through the monitor and returns the boundary-crossing
    /// events it produced — usually empty, at most one per zone.
    ///
    /// This is the synchronous heart of the monitor. The adapter calls it inline
    /// on the location stream it already consumes (so risk monitoring adds no
    /// second location subscription); `events(in:)` wraps it for stream-in,
    /// stream-out use and the tests.
    public mutating func evaluate(_ sample: LocationSample) -> [RiskEvent] {
        var events: [RiskEvent] = []
        for index in zones.indices {
            let zone = zones[index]
            let distance = sample.proximity(to: zone)
            let previous = levels[index]
            let current = level(for: distance, in: zone)
            levels[index] = current

            guard current != previous else { continue }

            if current == .inside {
                // Crossed inward across the radius from anywhere outside it.
                events.append(RiskEvent(kind: .entered, zone: zone, distance: distance, sample: sample))
            } else if previous == .inside {
                // Crossed outward across the radius (to approaching or fully out).
                events.append(RiskEvent(kind: .exited, zone: zone, distance: distance, sample: sample))
            } else if current == .approaching {
                // First step from fully outside into the warning band. The
                // `previous == .inside` case is handled above, so this is only
                // ever an outside → approaching transition.
                events.append(RiskEvent(kind: .approaching, zone: zone, distance: distance, sample: sample))
            }
        }
        return events
    }

    /// Consumes a stream of samples and emits the resulting risk events as their
    /// own stream, finishing when the input finishes or the consumer cancels.
    ///
    /// This is the headline form named in the design: a `RiskMonitor` "consumes
    /// the AsyncStream and emits a typed RiskEvent". The mutable evaluation state
    /// is created and confined inside the consuming task, so the monitor's value
    /// semantics are preserved and nothing crosses a concurrency boundary mutably.
    public func events(in samples: AsyncStream<LocationSample>) -> AsyncStream<RiskEvent> {
        let zones = self.zones
        let approachingMargin = self.approachingMargin
        return AsyncStream { continuation in
            let task = Task {
                var monitor = RiskMonitor(zones: zones, approachingMargin: approachingMargin)
                for await sample in samples {
                    for event in monitor.evaluate(sample) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Classifies a distance into a membership level for `zone`.
    private func level(for distance: Double, in zone: RiskZone) -> Level {
        if distance <= zone.radius {
            return .inside
        }
        if distance <= zone.radius + approachingMargin {
            return .approaching
        }
        return .outside
    }
}
