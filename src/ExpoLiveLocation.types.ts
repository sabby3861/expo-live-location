/**
 * Authorization state for location access, collapsed to the three outcomes a
 * caller acts on. Mirrors the native `PermissionStatus`.
 */
export type PermissionStatus = 'granted' | 'denied' | 'undetermined';

/**
 * A single location reading delivered across the native bridge.
 *
 * Values mirror CoreLocation's semantics: `speed` is negative when unavailable,
 * and `timestamp` is milliseconds since the Unix epoch (ready for `new Date()`).
 */
export type LocationSample = {
  latitude: number;
  longitude: number;
  /** Meters above sea level. */
  altitude: number;
  /** Meters per second; negative when unavailable. */
  speed: number;
  /** Radius of horizontal uncertainty in meters; negative when invalid. */
  horizontalAccuracy: number;
  /** Milliseconds since the Unix epoch. */
  timestamp: number;
};

/**
 * A circular area to be alerted on, as passed to `setRiskZones`. Mirrors the
 * native `RiskZone`: a labelled center coordinate with a radius in meters.
 */
export type RiskZone = {
  /** A short, human-readable label shown with the alert. */
  name: string;
  /** Center latitude in WGS-84 degrees. */
  latitude: number;
  /** Center longitude in WGS-84 degrees. */
  longitude: number;
  /** Radius in meters. Must be positive; invalid zones are ignored natively. */
  radius: number;
};

/**
 * The kind of zone boundary crossing reported by an `onRiskAlert` event.
 *
 * - `entered` — the device moved inside a zone's radius.
 * - `exited` — the device moved back outside a zone's radius.
 * - `approaching` — the device came within the monitor's margin of a zone but is
 *   not yet inside it.
 */
export type RiskEventKind = 'entered' | 'exited' | 'approaching';

/**
 * The payload of an `onRiskAlert` event: a single boundary crossing, flattened
 * for the bridge. `timestamp` follows the same convention as `LocationSample`.
 */
export type RiskAlert = {
  /** What happened at the boundary. */
  kind: RiskEventKind;
  /** The name of the zone the alert concerns. */
  zone: string;
  /** Distance in meters from the triggering location to the zone center. */
  distance: number;
  /** Latitude of the triggering location. */
  latitude: number;
  /** Longitude of the triggering location. */
  longitude: number;
  /** Milliseconds since the Unix epoch. */
  timestamp: number;
};

/**
 * The native module's event map. Keys are event names; values are the listener
 * signatures, which gives `addListener` full type inference on the payload.
 */
export type ExpoLiveLocationModuleEvents = {
  onLocationUpdate: (sample: LocationSample) => void;
  onRiskAlert: (alert: RiskAlert) => void;
};
