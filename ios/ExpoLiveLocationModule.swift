import ExpoModulesCore
import LiveLocationKit

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

    /// Created lazily on the main thread to honor `SystemLocationSource`'s
    /// contract: CoreLocation delivers authorization callbacks on the run loop of
    /// the thread that created the manager, and Expo module init is not
    /// guaranteed to be the main thread.
    private lazy var provider: LiveLocationProvider = Self.makeProviderOnMain()

    /// The task consuming `provider.locationUpdates()`. Non-nil exactly while the
    /// native stream is active.
    private var streamTask: Task<Void, Never>?

    public func definition() -> ModuleDefinition {
        Name("ExpoLiveLocation")

        Events(Self.locationEvent)

        AsyncFunction("requestPermission") { () async -> String in
            PermissionStatus(await self.provider.requestAuthorization()).rawValue
        }

        AsyncFunction("getCurrentLocation") { () async throws -> LocationSampleRecord in
            LocationSampleRecord(try await self.provider.currentLocation())
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
        guard streamTask == nil else { return }
        let provider = self.provider
        streamTask = Task { [weak self] in
            for await sample in provider.locationUpdates() {
                guard let self else { break }
                self.sendEvent(Self.locationEvent, LocationSampleRecord(sample).toDictionary())
            }
        }
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
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
