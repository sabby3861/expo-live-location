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
 * The native module's event map. Keys are event names; values are the listener
 * signatures, which gives `addListener` full type inference on the payload.
 */
export type ExpoLiveLocationModuleEvents = {
  onLocationUpdate: (sample: LocationSample) => void;
};
