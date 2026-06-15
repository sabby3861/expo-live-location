import Foundation
@testable import LiveLocationKit

/// A `LocationSourcing` test double that emits a scripted sequence of samples and
/// can simulate any authorization outcome — including denial — without touching
/// CoreLocation or a simulator.
///
/// It also records how many times `updates()` was called and how many streams are
/// currently active, so tests can assert that repeated start/stop cycles leave no
/// stream running.
final class MockLocationSource: LocationSourcing, @unchecked Sendable {

    private let scriptedSamples: [LocationSample]
    private let authorization: LocationAuthorizationStatus
    private let lock = NSLock()

    private var _updatesCallCount = 0
    private var _activeStreamCount = 0

    /// The number of times `updates()` has been invoked.
    var updatesCallCount: Int { lock.withLock { _updatesCallCount } }
    /// The number of streams that have started but not yet terminated.
    var activeStreamCount: Int { lock.withLock { _activeStreamCount } }

    /// - Parameters:
    ///   - scripted: The samples each stream emits, in order, before finishing.
    ///   - authorization: The status returned from `requestAuthorization()` and
    ///     used to decide whether `currentLocation()`/`updates()` succeed.
    init(
        scripted: [LocationSample] = [],
        authorization: LocationAuthorizationStatus = .authorizedWhenInUse
    ) {
        self.scriptedSamples = scripted
        self.authorization = authorization
    }

    func requestAuthorization() async -> LocationAuthorizationStatus {
        authorization
    }

    func currentLocation() async throws -> LocationSample {
        switch authorization {
        case .denied: throw LocationError.denied
        case .restricted: throw LocationError.restricted
        case .notDetermined, .authorizedWhenInUse, .authorizedAlways:
            guard let first = scriptedSamples.first else { throw LocationError.locationUnavailable }
            return first
        }
    }

    func updates() -> AsyncStream<LocationSample> {
        lock.withLock {
            _updatesCallCount += 1
            _activeStreamCount += 1
        }

        let samples = scriptedSamples
        let isAuthorized = authorization.isAuthorized

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?._activeStreamCount -= 1 }
            }
            guard isAuthorized else {
                continuation.finish()
                return
            }
            for sample in samples {
                continuation.yield(sample)
            }
            continuation.finish()
        }
    }
}
