/// The public entry point of LiveLocationKit and the single surface the Expo
/// adapter talks to.
///
/// It is deliberately thin: it owns a `LocationSourcing` dependency and forwards
/// to it. All CoreLocation logic lives behind the injected source, so this type
/// — and everything layered above it — can be tested with a mock. Construct it
/// with the default initializer in production, or inject a source in tests.
public struct LiveLocationProvider: Sendable {

    private let source: LocationSourcing

    /// Creates a provider.
    ///
    /// - Parameter source: The location source to read from. Defaults to
    ///   `SystemLocationSource`, the CoreLocation-backed implementation. Inject a
    ///   custom source — typically a mock — to drive the provider in tests.
    public init(source: LocationSourcing = SystemLocationSource()) {
        self.source = source
    }

    /// Requests "when in use" authorization and resolves with the resulting
    /// status. See `LocationSourcing.requestAuthorization()`.
    public func requestAuthorization() async -> LocationAuthorizationStatus {
        await source.requestAuthorization()
    }

    /// Resolves a single, most-recent location, throwing `LocationError` when one
    /// cannot be produced. See `LocationSourcing.currentLocation()`.
    public func currentLocation() async throws -> LocationSample {
        try await source.currentLocation()
    }

    /// A stream of live location updates. See `LocationSourcing.updates()`.
    public func locationUpdates() -> AsyncStream<LocationSample> {
        source.updates()
    }
}
