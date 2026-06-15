import { NativeModule, requireNativeModule } from 'expo-modules-core';

import type {
  ExpoLiveLocationModuleEvents,
  LocationSample,
  PermissionStatus,
} from './ExpoLiveLocation.types';

/**
 * Typed handle to the native module. Extending `NativeModule` with the event map
 * makes `addListener('onLocationUpdate', …)` fully typed and returns an
 * `EventSubscription` with a `.remove()` method for cleanup.
 */
declare class ExpoLiveLocationModule extends NativeModule<ExpoLiveLocationModuleEvents> {
  /** Requests "when in use" authorization and resolves with the outcome. */
  requestPermission(): Promise<PermissionStatus>;
  /** Resolves a single, most-recent location; rejects if it cannot be produced. */
  getCurrentLocation(): Promise<LocationSample>;
  /** Begins streaming `onLocationUpdate` events. Idempotent. */
  startUpdates(): void;
  /** Stops streaming. Idempotent. */
  stopUpdates(): void;
}

// `requireNativeModule` looks the module up by its registered `Name(...)`.
export default requireNativeModule<ExpoLiveLocationModule>('ExpoLiveLocation');
