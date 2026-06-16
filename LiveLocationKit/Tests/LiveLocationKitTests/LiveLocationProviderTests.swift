import XCTest
@testable import LiveLocationKit

/// Behavioral tests for the public provider, driven entirely through the
/// `LocationSourcing` seam with `MockLocationSource`. No simulator or device is
/// involved, so the suite is deterministic and runs with plain `swift test`.
final class LiveLocationProviderTests: XCTestCase {

    private func sample(lat: Double, lon: Double, at time: TimeInterval = 0) -> LocationSample {
        LocationSample(
            coordinate: .init(latitude: lat, longitude: lon),
            altitude: 0,
            speed: -1,
            horizontalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: time)
        )
    }

    func testUpdatesEmitExpectedSamplesInOrder() async {
        let scripted = [
            sample(lat: 37.0, lon: -122.0, at: 1),
            sample(lat: 37.1, lon: -122.1, at: 2),
            sample(lat: 37.2, lon: -122.2, at: 3),
        ]
        let provider = LiveLocationProvider(source: MockLocationSource(scripted: scripted))

        var received: [LocationSample] = []
        for await location in provider.locationUpdates() {
            received.append(location)
        }

        XCTAssertEqual(received, scripted)
    }

    func testStreamFinishesCleanlyAfterEmitting() async {
        let mock = MockLocationSource(scripted: [sample(lat: 1, lon: 1)])
        let provider = LiveLocationProvider(source: mock)

        var count = 0
        for await _ in provider.locationUpdates() {
            count += 1
        }
        await Task.yield()

        XCTAssertEqual(count, 1, "stream should deliver every scripted sample then finish")
        XCTAssertEqual(mock.activeStreamCount, 0, "stream should not remain active after finishing")
    }

    func testDenialSurfacesAsLocationError() async {
        let provider = LiveLocationProvider(source: MockLocationSource(authorization: .denied))

        do {
            _ = try await provider.currentLocation()
            XCTFail("expected currentLocation() to throw on denial")
        } catch let error as LocationError {
            XCTAssertEqual(error, .denied)
        } catch {
            XCTFail("expected LocationError, got \(error)")
        }
    }

    func testRestrictionSurfacesAsLocationError() async {
        let provider = LiveLocationProvider(source: MockLocationSource(authorization: .restricted))

        do {
            _ = try await provider.currentLocation()
            XCTFail("expected currentLocation() to throw when restricted")
        } catch let error as LocationError {
            XCTAssertEqual(error, .restricted)
        } catch {
            XCTFail("expected LocationError, got \(error)")
        }
    }

    func testDeniedAuthorizationProducesEmptyStream() async {
        let mock = MockLocationSource(
            scripted: [sample(lat: 1, lon: 1)],
            authorization: .denied
        )
        let provider = LiveLocationProvider(source: mock)

        var received: [LocationSample] = []
        for await location in provider.locationUpdates() {
            received.append(location)
        }

        XCTAssertTrue(received.isEmpty, "a denied source must not emit locations")
    }

    func testRepeatedStartStopLeavesNoActiveStreams() async {
        let mock = MockLocationSource(scripted: [sample(lat: 1, lon: 1), sample(lat: 2, lon: 2)])
        let provider = LiveLocationProvider(source: mock)

        for _ in 0..<3 {
            for await _ in provider.locationUpdates() {}
        }
        await Task.yield()

        XCTAssertEqual(mock.updatesCallCount, 3, "each start should open a fresh stream")
        XCTAssertEqual(mock.activeStreamCount, 0, "every stream should have terminated")
    }

    func testConsumerCancellationTerminatesStream() async {
        let scripted = (0..<50).map { sample(lat: Double($0), lon: 0, at: TimeInterval($0)) }
        let mock = MockLocationSource(scripted: scripted)
        let provider = LiveLocationProvider(source: mock)

        var received = 0
        for await _ in provider.locationUpdates() {
            received += 1
            if received == 1 { break }
        }
        await Task.yield()

        XCTAssertEqual(received, 1)
        XCTAssertEqual(mock.activeStreamCount, 0, "breaking out of iteration must terminate the stream")
    }

    func testRequestAuthorizationReportsResolvedStatus() async {
        let provider = LiveLocationProvider(source: MockLocationSource(authorization: .authorizedWhenInUse))
        let status = await provider.requestAuthorization()
        XCTAssertEqual(status, .authorizedWhenInUse)
    }

    func testCurrentLocationReturnsMostRecentSampleWhenAuthorized() async throws {
        let expected = sample(lat: 51.5, lon: -0.12, at: 99)
        let provider = LiveLocationProvider(source: MockLocationSource(scripted: [expected]))

        let location = try await provider.currentLocation()

        XCTAssertEqual(location, expected)
    }
}
