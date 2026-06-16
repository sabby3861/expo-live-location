import XCTest
@testable import LiveLocationKit

/// Behavioral tests for the risk layer, driven entirely by scripted coordinates —
/// through `MockLocationSource` for the streaming path and directly for the
/// synchronous state machine. No simulator or device is involved.
final class RiskMonitorTests: XCTestCase {

    // A zone centered on the equator/prime-meridian origin keeps the geometry easy
    // to reason about: ~111.32 km per degree of longitude at the equator.
    private let origin = LocationSample.Coordinate(latitude: 0, longitude: 0)

    private func sample(lat: Double, lon: Double, at time: TimeInterval = 0) -> LocationSample {
        LocationSample(
            coordinate: .init(latitude: lat, longitude: lon),
            altitude: 0,
            speed: -1,
            horizontalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: time)
        )
    }

    /// Collects every event a monitor emits for a scripted run fed through the
    /// mock source — the required "MockLocationSource feeding scripted coordinates"
    /// path, exercising the real `AsyncStream` plumbing.
    private func events(
        zones: [RiskZone],
        margin: Double,
        coordinates: [LocationSample]
    ) async -> [RiskEvent] {
        let mock = MockLocationSource(scripted: coordinates)
        let monitor = RiskMonitor(zones: zones, approachingMargin: margin)
        var collected: [RiskEvent] = []
        for await event in monitor.events(in: mock.updates()) {
            collected.append(event)
        }
        return collected
    }

    // MARK: - proximity

    func testProximityIsDistanceToCenterInMeters() {
        // One degree of latitude is ~111.32 km anywhere on the globe.
        let here = sample(lat: 0, lon: 0)
        let zone = RiskZone(name: "Origin", center: .init(latitude: 1, longitude: 0), radius: 100)
        let distance = here.proximity(to: zone)
        XCTAssertEqual(distance, 110_574, accuracy: 2_000, "≈111 km for one degree of latitude")
    }

    // MARK: - synchronous state machine

    func testFirstFixInsideZoneFiresEntered() {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        var monitor = RiskMonitor(zones: [zone], approachingMargin: 250)

        // ~111 m north of center — comfortably inside a 500 m radius.
        let events = monitor.evaluate(sample(lat: 0.001, lon: 0))

        XCTAssertEqual(events.map(\.kind), [.entered])
        XCTAssertEqual(events.first?.zone, zone)
    }

    func testStationaryDeviceInsideZoneEmitsOnlyOnce() {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        var monitor = RiskMonitor(zones: [zone], approachingMargin: 250)

        let first = monitor.evaluate(sample(lat: 0.001, lon: 0, at: 1))
        let second = monitor.evaluate(sample(lat: 0.001, lon: 0, at: 2))
        let third = monitor.evaluate(sample(lat: 0.0011, lon: 0, at: 3))

        XCTAssertEqual(first.map(\.kind), [.entered])
        XCTAssertTrue(second.isEmpty, "no event while remaining inside")
        XCTAssertTrue(third.isEmpty, "no event while remaining inside")
    }

    func testApproachThenEnterThenExitSequence() async {
        // radius 500 m, margin 500 m → approaching band is 500–1000 m from center.
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        let track = [
            sample(lat: 0.030, lon: 0, at: 0),   // ~3338 m — fully outside
            sample(lat: 0.007, lon: 0, at: 1),   // ~779 m  — approaching band
            sample(lat: 0.002, lon: 0, at: 2),   // ~222 m  — inside
            sample(lat: 0.007, lon: 0, at: 3),   // ~779 m  — back to approaching (exit radius)
            sample(lat: 0.030, lon: 0, at: 4),   // ~3338 m — fully outside again
        ]

        let kinds = await events(zones: [zone], margin: 500, coordinates: track).map(\.kind)

        XCTAssertEqual(kinds, [.approaching, .entered, .exited])
    }

    func testInsideToApproachingIsExitNotApproaching() {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        var monitor = RiskMonitor(zones: [zone], approachingMargin: 500)

        _ = monitor.evaluate(sample(lat: 0.002, lon: 0, at: 0))   // inside → entered
        let events = monitor.evaluate(sample(lat: 0.007, lon: 0, at: 1)) // 779 m → approaching band

        XCTAssertEqual(events.map(\.kind), [.exited], "leaving the radius is an exit, never a second approaching")
    }

    func testLargeJumpFromOutsideToInsideStillFiresEntered() {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        var monitor = RiskMonitor(zones: [zone], approachingMargin: 100)

        _ = monitor.evaluate(sample(lat: 0.030, lon: 0, at: 0))   // far outside
        let events = monitor.evaluate(sample(lat: 0.001, lon: 0, at: 1)) // straight inside

        XCTAssertEqual(events.map(\.kind), [.entered], "skipping the approaching band still enters")
    }

    func testZeroMarginNeverFiresApproaching() {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        var monitor = RiskMonitor(zones: [zone], approachingMargin: 0)

        // ~779 m out: with no margin this is fully outside, not approaching.
        let approaching = monitor.evaluate(sample(lat: 0.007, lon: 0, at: 0))
        let entered = monitor.evaluate(sample(lat: 0.001, lon: 0, at: 1))

        XCTAssertTrue(approaching.isEmpty, "a zero margin suppresses approaching warnings")
        XCTAssertEqual(entered.map(\.kind), [.entered])
    }

    func testDistanceCarriedOnEventMatchesProximity() {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        var monitor = RiskMonitor(zones: [zone], approachingMargin: 250)

        let inside = sample(lat: 0.002, lon: 0)
        let events = monitor.evaluate(inside)

        XCTAssertEqual(events.first?.distance, inside.proximity(to: zone))
    }

    // MARK: - multiple zones

    func testIndependentZonesEachTrackSeparately() {
        let near = RiskZone(name: "Near", center: origin, radius: 500)
        let far = RiskZone(name: "Far", center: .init(latitude: 1, longitude: 0), radius: 500)
        var monitor = RiskMonitor(zones: [near, far], approachingMargin: 250)

        // Inside "Near", nowhere near "Far".
        let events = monitor.evaluate(sample(lat: 0.001, lon: 0))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.zone, near)
    }

    // MARK: - empty configuration

    func testNoZonesProducesNoEvents() async {
        let track = (0..<5).map { sample(lat: Double($0) * 0.001, lon: 0, at: TimeInterval($0)) }
        let events = await events(zones: [], margin: 250, coordinates: track)
        XCTAssertTrue(events.isEmpty, "a monitor with no zones is inert")
    }

    func testStreamFinishesWhenSourceFinishes() async {
        let zone = RiskZone(name: "Harbor", center: origin, radius: 500)
        let mock = MockLocationSource(scripted: [sample(lat: 0.001, lon: 0)])
        let monitor = RiskMonitor(zones: [zone], approachingMargin: 250)

        var count = 0
        for await _ in monitor.events(in: mock.updates()) {
            count += 1
        }
        await Task.yield()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(mock.activeStreamCount, 0, "the upstream location stream must terminate with the risk stream")
    }
}
