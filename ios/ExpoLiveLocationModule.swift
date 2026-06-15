import ExpoModulesCore

// LiveLocationKit's sources are compiled into this pod target in place (see the
// podspec's source_files), so its public types are visible here without an import.

/// The Expo adapter for LiveLocationKit.
///
/// It is intentionally a thin translation layer with no business logic: every
/// location decision lives in `LiveLocationProvider`. The adapter only
/// - converts authorization/sample values into bridge-friendly shapes,
/// - exposes imperative `start/stopUpdates` functions, and
/// - gates the native stream on JavaScript listener presence via
///   `OnStartObserving`/`OnStopObserving`.
///
/// There is a single source of truth for "is the stream running": the presence
/// of `streamTask`. Both the imperative functions and the observing hooks route
/// through `startStreaming()`/`stopStreaming()`, so listeners and explicit calls
/// can never double-start or leak the consumer task.
public final class ExpoLiveLocationModule: Module {

    private static let locationEvent = "onLocationUpdate"
    private static let riskEvent = "onRiskAlert"

    /// Backing storage for the provider and its construction lock. A plain
    /// `lazy var` is not safe here: Expo can dispatch the async functions and the
    /// observing hooks on different threads, and a racing first access could build
    /// two providers (two `CLLocationManager`s). `resolvedProvider()` guarantees a
    /// single instance, created once on the main thread.
    private let providerLock = NSLock()
    private var _provider: LiveLocationProvider?

    /// Guards `streamTask` and `streamGeneration`. The start/stop entry points are
    /// reachable from both the imperative functions and the observing hooks, which
    /// Expo may invoke from different threads, so the running state is locked.
    private let streamLock = NSLock()

    /// The task consuming `provider.locationUpdates()`. Non-nil exactly while the
    /// native stream is active.
    private var streamTask: Task<Void, Never>?

    /// Bumped on every start and stop. A task that finishes on its own clears
    /// `streamTask` only if its generation is still current, so a stream that ends
    /// naturally (e.g. authorization revoked mid-stream) cannot wipe out a newer
    /// stream that a subsequent start already installed.
    private var streamGeneration = 0

    /// Guards `riskMonitor`. Deliberately separate from `streamLock`: the stream
    /// loop evaluates risk per sample and `setRiskZones` replaces the monitor, and
    /// the two locks are never held together, so they cannot deadlock.
    private let riskLock = NSLock()

    /// The risk state machine. Starts empty (no zones, so no alerts) and is rebuilt
    /// by `setRiskZones`. Its membership state intentionally persists across
    /// stream stop/start — only a new zone configuration resets it — so a device
    /// that never left a zone does not re-fire `.entered` when streaming resumes.
    private var riskMonitor = RiskMonitor(zones: [])

    public func definition() -> ModuleDefinition {
        Name("ExpoLiveLocation")

        Events(Self.locationEvent, Self.riskEvent)

        AsyncFunction("requestPermission") { () async -> String in
            PermissionStatus(await self.resolvedProvider().requestAuthorization()).rawValue
        }

        AsyncFunction("getCurrentLocation") { () async throws -> LocationSampleRecord in
            LocationSampleRecord(try await self.resolvedProvider().currentLocation())
        }

        Function("setRiskZones") { (zones: [RiskZoneRecord]) in
            self.updateRiskZones(zones)
        }

        Function("startUpdates") {
            self.startStreaming()
        }

        Function("stopUpdates") {
            self.stopStreaming()
        }

        OnStartObserving {
            self.startStreaming()
        }

        OnStopObserving {
            self.stopStreaming()
        }
    }

    private func startStreaming() {
        // Resolve the provider before taking streamLock so the two locks never nest.
        let provider = resolvedProvider()
        streamLock.lock()
        guard streamTask == nil else {
            streamLock.unlock()
            return
        }
        streamGeneration += 1
        let generation = streamGeneration
        streamTask = Task { [weak self] in
            for await sample in provider.locationUpdates() {
                guard let self else { break }
                self.sendEvent(Self.locationEvent, LocationSampleRecord(sample).toDictionary())
                self.emitRiskAlerts(for: sample)
            }
            // The stream finished on its own (e.g. authorization revoked). Clear the
            // running flag so a future start can begin again.
            self?.finishStreaming(generation: generation)
        }
        streamLock.unlock()
    }

    private func stopStreaming() {
        streamLock.lock()
        let task = streamTask
        streamTask = nil
        // Invalidate any in-flight natural completion so it cannot clear a stream
        // that a later start installs.
        streamGeneration += 1
        streamLock.unlock()
        task?.cancel()
    }

    /// Replaces the monitored zones with the valid entries of `records`.
    ///
    /// Invalid zones (non-finite numbers, non-positive radius, out-of-range
    /// coordinates) are dropped by `RiskZoneRecord.riskZone()`. Installing a new
    /// configuration starts the risk state fresh, so the next sample is classified
    /// against the new zones from a clean slate.
    private func updateRiskZones(_ records: [RiskZoneRecord]) {
        let zones = records.compactMap { $0.riskZone() }
        riskLock.lock()
        riskMonitor = RiskMonitor(zones: zones)
        riskLock.unlock()
    }

    /// Evaluates one sample against the current zones and emits an `onRiskAlert`
    /// for each boundary crossing. The monitor is mutated under `riskLock`; the
    /// resulting events are sent after the lock is released so the bridge call
    /// never happens while holding it.
    private func emitRiskAlerts(for sample: LocationSample) {
        riskLock.lock()
        let alerts = riskMonitor.evaluate(sample)
        riskLock.unlock()
        for alert in alerts {
            sendEvent(Self.riskEvent, RiskEventRecord(alert).toDictionary())
        }
    }

    private func finishStreaming(generation: Int) {
        streamLock.lock()
        if generation == streamGeneration {
            streamTask = nil
        }
        streamLock.unlock()
    }

    /// Returns the single provider, constructing it on first use. Creation is
    /// serialized by `providerLock` and performed on the main thread to honor
    /// `SystemLocationSource`'s run-loop contract.
    private func resolvedProvider() -> LiveLocationProvider {
        providerLock.lock()
        defer { providerLock.unlock() }
        if let existing = _provider {
            return existing
        }
        let created = Self.makeProviderOnMain()
        _provider = created
        return created
    }

    private static func makeProviderOnMain() -> LiveLocationProvider {
        if Thread.isMainThread {
            return LiveLocationProvider()
        }
        return DispatchQueue.main.sync { LiveLocationProvider() }
    }
}

/// The bridge form of `LocationAuthorizationStatus`, collapsed to the three
/// states JavaScript callers act on. Defined here, at the adapter boundary, so
/// the domain enum stays free of Expo's permission vocabulary.
private enum PermissionStatus: String {
    case granted
    case denied
    case undetermined

    init(_ status: LocationAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: self = .granted
        case .denied, .restricted: self = .denied
        case .notDetermined: self = .undetermined
        }
    }
}
