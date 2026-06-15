import type { EventSubscription } from 'expo-modules-core';
import { useEffect, useState } from 'react';

import ExpoLiveLocation from './ExpoLiveLocationModule';
import type {
  LocationSample,
  PermissionStatus,
  RiskAlert,
  RiskZone,
} from './ExpoLiveLocation.types';

/** Options for `useLiveLocation`. */
export type UseLiveLocationOptions = {
  /**
   * Zones to monitor for risk alerts. When provided, the hook configures the
   * native monitor and reports crossings through `risk`. Changing the zones'
   * contents reconfigures the monitor; pass an empty array or omit to disable.
   */
  riskZones?: RiskZone[];
};

/** What `useLiveLocation` exposes to a component. */
export type UseLiveLocationResult = {
  /** The most recent sample, or `null` before the first update. */
  location: LocationSample | null;
  /** The resolved authorization status, or `null` while it is being requested. */
  permission: PermissionStatus | null;
  /** A permission/location failure, if one occurred. */
  error: Error | null;
  /**
   * The most recent risk alert, or `null` if none has fired. Only populated when
   * `riskZones` is supplied.
   */
  risk: RiskAlert | null;
};

/**
 * Subscribes to live location updates for the lifetime of the calling component,
 * and optionally to risk-zone crossings.
 *
 * On mount it requests authorization and, if granted, starts the native stream
 * and listens for updates. On unmount it removes the listener and stops the
 * stream, so the location source runs only while a component needs it. The
 * location effect runs once; all teardown happens in its cleanup function.
 *
 * Risk monitoring is handled by a second effect keyed on the zones' contents: it
 * configures the native monitor, subscribes to `onRiskAlert`, and tears both down
 * on unmount or when the zones change.
 */
export function useLiveLocation(options: UseLiveLocationOptions = {}): UseLiveLocationResult {
  const [location, setLocation] = useState<LocationSample | null>(null);
  const [permission, setPermission] = useState<PermissionStatus | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [risk, setRisk] = useState<RiskAlert | null>(null);

  // Serialize the zones so the risk effect re-runs only when their contents
  // change, not on every render that passes a fresh array literal.
  const zonesKey = options.riskZones ? JSON.stringify(options.riskZones) : null;

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

  useEffect(() => {
    if (!zonesKey) {
      return;
    }
    const zones: RiskZone[] = JSON.parse(zonesKey);
    ExpoLiveLocation.setRiskZones(zones);
    const subscription = ExpoLiveLocation.addListener('onRiskAlert', setRisk);

    return () => {
      subscription.remove();
      ExpoLiveLocation.setRiskZones([]);
      setRisk(null);
    };
  }, [zonesKey]);

  return { location, permission, error, risk };
}
