/// The dependency-injection seam between the public provider and whatever
/// actually produces locations.
///
/// Production code uses `SystemLocationSource` (backed by CoreLocation); tests
/// inject a mock that emits a scripted sequence. Because everything above this
/// protocol depends only on the abstraction, the entire stack can be exercised
/// without a device or simulator.
public protocol LocationSourcing: Sendable {

    /// Requests "when in use" authorization if the status is undetermined and
    /// resolves with the resulting status. If authorization has already been
    /// decided, the current status is returned without prompting.
    func requestAuthorization() async -> LocationAuthorizationStatus

    /// Resolves a single, most-recent location.
    ///
    /// - Throws: `LocationError.denied` or `.restricted` when authorization does
    ///   not permit access, or `.locationUnavailable` when no fix can be made.
    func currentLocation() async throws -> LocationSample

    /// A stream of location updates that runs until the consumer stops iterating
    /// or cancels the surrounding task.
    ///
    /// The stream finishes (rather than throwing) when updates can no longer be
    /// produced — for example if authorization is revoked mid-stream — keeping
    /// the element type a plain `LocationSample`. Use `requestAuthorization()`
    /// or `currentLocation()` when you need an explicit error.
    func updates() -> AsyncStream<LocationSample>
}
