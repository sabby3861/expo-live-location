import type { EventSubscription } from 'expo-modules-core';
import { useEffect, useState } from 'react';

import ExpoLiveLocation from './ExpoLiveLocationModule';
import type { LocationSample, PermissionStatus } from './ExpoLiveLocation.types';

/** What `useLiveLocation` exposes to a component. */
export type UseLiveLocationResult = {
  /** The most recent sample, or `null` before the first update. */
  location: LocationSample | null;
  /** The resolved authorization status, or `null` while it is being requested. */
  permission: PermissionStatus | null;
  /** A permission/location failure, if one occurred. */
  error: Error | null;
};

/**
 * Subscribes to live location updates for the lifetime of the calling component.
 *
 * On mount it requests authorization and, if granted, starts the native stream
 * and listens for updates. On unmount it removes the listener and stops the
 * stream, so the location source runs only while a component needs it. The
 * effect runs once; all teardown happens in its cleanup function.
 */
export function useLiveLocation(): UseLiveLocationResult {
  const [location, setLocation] = useState<LocationSample | null>(null);
  const [permission, setPermission] = useState<PermissionStatus | null>(null);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let cancelled = false;
    let subscription: EventSubscription | undefined;

    (async () => {
      try {
        const status = await ExpoLiveLocation.requestPermission();
        if (cancelled) {
          return;
        }
        setPermission(status);
        if (status !== 'granted') {
          return;
        }
        subscription = ExpoLiveLocation.addListener('onLocationUpdate', setLocation);
        ExpoLiveLocation.startUpdates();
      } catch (caught) {
        if (!cancelled) {
          setError(caught instanceof Error ? caught : new Error(String(caught)));
        }
      }
    })();

    return () => {
      cancelled = true;
      subscription?.remove();
      ExpoLiveLocation.stopUpdates();
    };
  }, []);

  return { location, permission, error };
}
