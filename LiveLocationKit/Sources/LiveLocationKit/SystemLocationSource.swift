@preconcurrency import CoreLocation
import Foundation

/// The production `LocationSourcing` implementation, backed by CoreLocation.
///
/// Two strategies sit behind one `AsyncStream` abstraction:
/// - **iOS 17+ / macOS 14+:** `CLLocationUpdate.liveUpdates()`, an async sequence
///   that needs no delegate and cancels cleanly with its enclosing task.
/// - **iOS 16 fallback:** a `CLLocationManagerDelegate` whose callbacks are
///   bridged into the same stream.
///
/// All mutable state is guarded by a lock and the type is `Sendable`, so it is
/// safe to call from any task and safe to start and stop streaming repeatedly.
///
/// - Important: Instantiate on the main thread. CoreLocation delivers delegate
///   callbacks (used by the iOS 16 fallback and by all authorization changes) on
///   the run loop of the thread that created the manager.
public final class SystemLocationSource: NSObject, LocationSourcing, @unchecked Sendable {

    private let manager: CLLocationManager
    private let lock = NSLock()

    /// Continuations awaiting the resolution of an authorization prompt.
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorizationStatus, Never>] = []
    /// Continuations awaiting a single location on the iOS 16 fallback path.
    private var oneShotWaiters: [CheckedContinuation<LocationSample, Error>] = []
    /// Active streaming continuations (iOS 16 fallback path), keyed for removal.
    private var streamContinuations: [UUID: AsyncStream<LocationSample>.Continuation] = [:]

    /// Creates a source backed by a fresh `CLLocationManager`.
    ///
    /// - Important: Construct instances on the main thread. CoreLocation delivers
    ///   delegate callbacks on the run loop of the thread that created the manager,
    ///   and authorization changes flow through that delegate on every path.
    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - LocationSourcing

    public func requestAuthorization() async -> LocationAuthorizationStatus {
        let status = LocationAuthorizationStatus(manager.authorizationStatus)
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { continuation in
            lock.withLock { authorizationWaiters.append(continuation) }
            performOnManager { $0.requestWhenInUseAuthorization() }
        }
    }

    public func currentLocation() async throws -> LocationSample {
        try await ensureAuthorized()

        if #available(iOS 17.0, macOS 14.0, *) {
            return try await firstLiveUpdate()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock { oneShotWaiters.append(continuation) }
                performOnManager { $0.requestLocation() }
            }
        }
    }

    public func updates() -> AsyncStream<LocationSample> {
        AsyncStream { continuation in
            if #available(iOS 17.0, macOS 14.0, *) {
                self.streamWithLiveUpdates(into: continuation)
            } else {
                self.streamWithDelegate(into: continuation)
            }
        }
    }

    // MARK: - Authorization helpers

    /// Throws unless the current authorization permits location access,
    /// prompting once if the decision has not yet been made.
    private func ensureAuthorized() async throws {
        var status = LocationAuthorizationStatus(manager.authorizationStatus)
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return
        case .denied: throw LocationError.denied
        case .restricted: throw LocationError.restricted
        case .notDetermined: throw LocationError.locationUnavailable
        }
    }

    // MARK: - iOS 17+ live updates

    @available(iOS 17.0, macOS 14.0, *)
    private func firstLiveUpdate() async throws -> LocationSample {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if #available(iOS 18.0, macOS 15.0, *), update.authorizationDenied {
                    throw LocationError.denied
                }
                if let location = update.location {
                    return LocationSample(location)
                }
            }
            throw LocationError.locationUnavailable
        } catch let error as LocationError {
            throw error
        } catch {
            throw LocationError(error)
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    private func streamWithLiveUpdates(into continuation: AsyncStream<LocationSample>.Continuation) {
        let task = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if #available(iOS 18.0, macOS 15.0, *), update.authorizationDenied {
                        break
                    }
                    if let location = update.location {
                        continuation.yield(LocationSample(location))
                    }
                }
            } catch {
                // The element type is non-throwing by design: a failed sequence
                // simply ends the stream. Callers needing the reason use
                // `currentLocation()` or `requestAuthorization()`.
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }

    // MARK: - iOS 16 delegate fallback

    private func streamWithDelegate(into continuation: AsyncStream<LocationSample>.Continuation) {
        let id = UUID()
        let isFirst = lock.withLock {
            streamContinuations[id] = continuation
            return streamContinuations.count == 1
        }

        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            let isEmpty = self.lock.withLock {
                self.streamContinuations[id] = nil
                return self.streamContinuations.isEmpty
            }
            if isEmpty {
                self.performOnManager { $0.stopUpdatingLocation() }
            }
        }

        if isFirst {
            performOnManager { $0.startUpdatingLocation() }
        }
    }

    // MARK: - Manager access

    /// Runs `body` against the manager on the main actor. CoreLocation's mutating
    /// calls are not concurrency-safe, so they are funneled to a single executor.
    private func performOnManager(_ body: @escaping @Sendable (CLLocationManager) -> Void) {
        Task { @MainActor in body(self.manager) }
    }
}

// MARK: - CLLocationManagerDelegate

extension SystemLocationSource: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = LocationAuthorizationStatus(manager.authorizationStatus)
        guard status != .notDetermined else { return }

        let waiters = lock.withLock {
            let pending = authorizationWaiters
            authorizationWaiters.removeAll()
            return pending
        }
        for waiter in waiters {
            waiter.resume(returning: status)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let sample = LocationSample(latest)

        let (streams, oneShots) = lock.withLock {
            let pendingOneShots = oneShotWaiters
            oneShotWaiters.removeAll()
            return (Array(streamContinuations.values), pendingOneShots)
        }
        for stream in streams {
            stream.yield(sample)
        }
        for oneShot in oneShots {
            oneShot.resume(returning: sample)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A one-shot `requestLocation()` reports its terminal failure here — and
        // that terminal error is frequently `.locationUnknown` when no fix could be
        // obtained — so its waiters must always be resolved or the `await` hangs.
        let oneShots = lock.withLock {
            let pending = oneShotWaiters
            oneShotWaiters.removeAll()
            return pending
        }
        if !oneShots.isEmpty {
            let mapped = LocationError(error)
            for oneShot in oneShots {
                oneShot.resume(throwing: mapped)
            }
        }

        // For continuous streaming, `.locationUnknown` is transient — CoreLocation
        // keeps trying — so the active streams are left running.
    }
}
