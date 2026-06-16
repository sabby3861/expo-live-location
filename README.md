# expo-live-location

Live iOS location for React Native, packaged as an Expo module. I built it to keep
all the CoreLocation work in a plain Swift package and treat the Expo bridge as a
thin shim on top, so the core logic can be tested without a simulator or a running
app.

<p align="center">
  <img src="docs/example-ios.png" alt="Example app showing a red Inside risk zone banner above a card with live coordinates, altitude, speed, and accuracy." width="300">
</p>

The Swift core (`LiveLocationKit`) imports nothing from Expo or React Native. It
hands out location as an `AsyncStream<LocationSample>` and runs on its own under
`swift test`. The Expo side only maps values across the bridge and starts/stops the
stream as JS listeners come and go, so location services aren't left running with
nothing reading them.

## How it fits together

```
        ┌──────────────────────────────────────────────────────────────┐
        │  Apple CoreLocation                                          │
        │  CLLocationUpdate.liveUpdates() · CLLocationManagerDelegate  │
        └───────────────────────────────┬──────────────────────────────┘
                                        │  (CoreLocation confined here)
        ┌───────────────────────────────▼──────────────────────────────┐
        │  SystemLocationSource            : LocationSourcing          │
        │  bridges both OS paths into one AsyncStream<LocationSample>  │
        └───────────────────────────────┬──────────────────────────────┘
                                        │  LocationSourcing  (DI seam)
        ┌───────────────────────────────▼──────────────────────────────┐
        │  LiveLocationProvider            — public entry point        │   pure Swift,
        │  thin, injectable, AsyncStream<LocationSample> out           │   no Expo / RN
        └───────────────────────────────┬──────────────────────────────┘
        ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   package boundary
        ┌───────────────────────────────▼──────────────────────────────┐
        │  ExpoLiveLocationModule          — thin Expo adapter         │
        │  Sample↔Record mapping · Events · OnStart/OnStopObserving    │
        └───────────────────────────────┬──────────────────────────────┘
                                        │  native module bridge
        ┌───────────────────────────────▼──────────────────────────────┐
        │  useLiveLocation()               — React hook                │
        │  subscribes on mount, removes listener + stops on unmount    │
        └──────────────────────────────────────────────────────────────┘
```

`CLLocationUpdate.liveUpdates()` runs on iOS 17+, with a `CLLocationManagerDelegate`
fallback for 16. Both feed the same stream, so nothing upstream has to care which
one ran. The source sits behind a `LocationSourcing` protocol, which is what lets
the tests drive everything with a mock.

There's also a risk-zone monitor. Give it circular zones and it emits
`entered` / `exited` / `approaching` as the device crosses them. Just geometry, no
maps and no network.

## Using it

```tsx
import { useLiveLocation } from 'expo-live-location';
import { Text, View } from 'react-native';

export default function Screen() {
  const { location, permission, error } = useLiveLocation();

  if (error) return <Text>{error.message}</Text>;
  if (permission !== 'granted') return <Text>Permission: {permission ?? '…'}</Text>;
  if (!location) return <Text>Waiting for first fix…</Text>;

  return (
    <View>
      <Text>{location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}</Text>
      <Text>±{location.horizontalAccuracy.toFixed(0)} m</Text>
    </View>
  );
}
```

Pass zones in and `risk` reports the latest crossing:

```tsx
const zones = [{ name: 'Harbor District', latitude: 37.3349, longitude: -122.009, radius: 600 }];
const { risk } = useLiveLocation({ riskZones: zones });
// risk?.kind is 'entered' | 'exited' | 'approaching', risk?.distance is meters
```

If you'd rather skip the hook there's a typed imperative API too:
`requestPermission()`, `getCurrentLocation()`, `startUpdates()`/`stopUpdates()`,
`setRiskZones()`, and the `onLocationUpdate` / `onRiskAlert` events. Add
`NSLocationWhenInUseUsageDescription` to your Info.plist (the example sets it in
`app.json`).

## Running it

Core tests:

```bash
cd LiveLocationKit && swift test
```

Uses Xcode's XCTest. If `xcode-select` points at the Command Line Tools, prefix it
with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The mock-backed
pieces are covered here; the live CoreLocation source only really exercises on a
device.

The example app:

```bash
npm install && npm run build
cd example && npm install
npx expo run:ios
```

It drops three demo zones near the simulator's default San Francisco location and
starts inside one, so the banner is red on launch. To watch it change, feed it
`example/route.gpx` (Xcode ▸ Debug ▸ Simulate Location), or move the simulator from
the terminal:

```bash
xcrun simctl location booted set 37.7896,-122.4103   # approaching
xcrun simctl location booted start --speed=12 \
  37.785800,-122.406400 37.792088,-122.412653 37.794603,-122.415154
```

## Layout

```
LiveLocationKit/   Swift package: the core and its tests
ios/               Expo adapter (the module + Record mapping)
src/               TS types and the useLiveLocation hook
example/           Expo app that consumes it
```

One wrinkle worth flagging: CocoaPods only picks up files under the podspec's own
folder. To keep a single copy of the Swift core and still compile it into the pod,
the podspec lives at the repo root (pointed at via `apple.podspecPath`) and globs
both `ios/` and `LiveLocationKit/Sources`. That's the only reason it isn't in
`ios/`.

## Requirements

iOS 16+, Expo SDK 56+. MIT licensed.
