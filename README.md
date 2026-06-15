# expo-live-location

Real-time iOS location for React Native, built the way a native SDK should be:
the device logic lives in a **pure Swift package** (`LiveLocationKit`) that has
zero dependency on Expo or React Native and exposes updates as a single
`AsyncStream<LocationSample>`. The Expo layer on top is a thin adapter — it
translates values across the JS bridge and gates the stream on listener
presence, and contains no location logic of its own. The result is a module that
is easy to reason about, fully typed end to end, and unit-tested without a
device or simulator.

<p align="center">
  <img src="docs/example-ios.png" alt="Example app: a Live Location screen with a red &quot;Inside risk zone&quot; banner above a card showing live coordinates, altitude, speed, and accuracy." width="300">
</p>

## Highlights

- **Decoupled core.** `LiveLocationKit` is a standalone Swift package. It builds
  and tests on its own (`swift test`, mock-only) and could be reused from any
  Swift app, not just this Expo module.
- **Modern concurrency.** `CLLocationUpdate.liveUpdates()` (iOS 17+) is the
  primary path; a `CLLocationManagerDelegate` fallback covers iOS 16. Both are
  surfaced through the *same* `AsyncStream`, so callers never branch on OS
  version.
- **Protocol-based dependency injection.** Everything above the
  `LocationSourcing` seam depends on the abstraction, so the whole stack is
  driven by a mock in tests.
- **Listener-driven lifecycle.** The native location source runs only while
  JavaScript holds a listener.
- **Typed all the way down.** No `any` in the TypeScript surface; a
  `useLiveLocation()` hook handles subscription and cleanup for you.
- **Risk-zone monitoring.** A pure `RiskMonitor` watches the same location stream
  against circular `RiskZone`s and emits typed `entered` / `exited` /
  `approaching` events as the device crosses boundaries — a traveller-safety
  primitive, fully unit-tested with scripted coordinates, no network or maps.

## Architecture

```
        ┌──────────────────────────────────────────────────────────────┐
        │  Apple CoreLocation                                            │
        │  CLLocationUpdate.liveUpdates() · CLLocationManagerDelegate    │
        └───────────────────────────────┬──────────────────────────────┘
                                         │  (CoreLocation confined here)
        ┌───────────────────────────────▼──────────────────────────────┐
        │  SystemLocationSource            : LocationSourcing            │
        │  bridges both OS paths into one AsyncStream<LocationSample>    │
        └───────────────────────────────┬──────────────────────────────┘
                                         │  LocationSourcing  (DI seam)
        ┌───────────────────────────────▼──────────────────────────────┐
        │  LiveLocationProvider            — public entry point         │   pure Swift,
        │  thin, injectable, AsyncStream<LocationSample> out            │   no Expo / RN
        └───────────────────────────────┬──────────────────────────────┘
        ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   package boundary
        ┌───────────────────────────────▼──────────────────────────────┐
        │  ExpoLiveLocationModule          — thin Expo adapter          │
        │  Sample↔Record mapping · Events · OnStart/OnStopObserving     │
        └───────────────────────────────┬──────────────────────────────┘
                                         │  native module bridge
        ┌───────────────────────────────▼──────────────────────────────┐
        │  useLiveLocation()               — React hook                 │
        │  subscribes on mount, removes listener + stops on unmount     │
        └────────────────────────────────────────────────────────────────┘
```

Type translation is confined to dedicated seams: `LocationSample ↔ CLLocation`
and `LocationSample ↔ Expo Record` each live in exactly one file, and the risk
layer's bridge (`RiskEvent`/`RiskZone ↔ Expo Record`) is likewise isolated to a
single file. CoreLocation is imported in exactly two files; Expo is imported only in
`ios/`.

## Usage

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

Prefer the imperative API? It is fully typed too:

```ts
import { ExpoLiveLocation } from 'expo-live-location';

const status = await ExpoLiveLocation.requestPermission(); // 'granted' | 'denied' | 'undetermined'
const here = await ExpoLiveLocation.getCurrentLocation();

const sub = ExpoLiveLocation.addListener('onLocationUpdate', (sample) => {
  console.log(sample.latitude, sample.longitude);
});
ExpoLiveLocation.startUpdates();
// later…
sub.remove();
ExpoLiveLocation.stopUpdates();
```

Add `NSLocationWhenInUseUsageDescription` to your app's `Info.plist` (the
`example/` app sets it via `app.json`).

### Risk zones

Pass circular zones to monitor and the hook reports the latest crossing through
`risk`:

```tsx
import { useLiveLocation, type RiskZone } from 'expo-live-location';

const zones: RiskZone[] = [
  { name: 'Harbor District', latitude: 37.3349, longitude: -122.009, radius: 600 },
];

function Screen() {
  const { location, risk } = useLiveLocation({ riskZones: zones });
  // risk?.kind is 'entered' | 'exited' | 'approaching'; risk?.distance is meters.
}
```

Or drive it imperatively:

```ts
import { ExpoLiveLocation } from 'expo-live-location';

ExpoLiveLocation.setRiskZones([
  { name: 'Harbor District', latitude: 37.3349, longitude: -122.009, radius: 600 },
]);
const sub = ExpoLiveLocation.addListener('onRiskAlert', (alert) => {
  console.log(alert.kind, alert.zone, alert.distance);
});
ExpoLiveLocation.startUpdates();
```

A device within a zone's radius is *inside* it (`entered` / `exited`); within a
configurable margin beyond the radius it is *approaching*. Events fire only on
boundary crossings, so a stationary device alerts once and then stays quiet. All
distance math is great-circle distance via CoreLocation — offline, no maps.

## Design decisions

**A pure Swift core, separate from Expo.** The native logic is a Swift Package
with no Expo or React Native import. This keeps the interesting code testable in
isolation (no simulator, no bridge), makes the CoreLocation surface reviewable in
one place, and means the core could be lifted into a pure-Swift app unchanged.
The Expo module depends on the package; the package never depends on Expo.

**One `AsyncStream`, two OS strategies.** `CLLocationUpdate.liveUpdates()` is a
clean async sequence with automatic cancellation, so it is the primary path. The
iOS 16 delegate fallback is bridged into an `AsyncStream` with the same element
type, so consumers — including the Expo adapter and the hook — write one loop
that works on every supported OS. Errors get a deliberate home rather than being
forced through a non-throwing stream: pre-flight `requestAuthorization()` and the
one-shot `currentLocation()` throw a typed `LocationError`, while the update
stream simply finishes if it can no longer produce values.

**Listener-driven lifecycle.** `OnStartObserving`/`OnStopObserving` start and stop
the underlying stream as JavaScript listeners come and go, so location services
are never left running when nothing is consuming them — the single source of
truth for "is the stream running" is one `Task` reference inside the adapter.
`startUpdates()`/`stopUpdates()` sit on top for imperative control and route
through the same start/stop, so they cannot double-start or leak.

## Project layout

```
LiveLocationKit/     Pure Swift package (the core). swift test runs here.
  Sources/           Domain types, LocationSourcing, SystemLocationSource, provider
  Tests/             MockLocationSource + behavioral tests
ios/                 Thin Expo adapter; podspec compiles the Kit sources in place
src/                 TypeScript surface + useLiveLocation hook
example/             Runnable Expo app that consumes the module
```

## Building & testing

The pure core is the part with real logic, and it is fully tested:

```bash
cd LiveLocationKit
swift test            # mock-only, deterministic, no simulator required
```

> `swift test` uses the Xcode toolchain (which provides XCTest). If your
> `xcode-select` points at the Command Line Tools, prefix the command with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Scope of what is verified, stated honestly:

- **Domain types, `LocationSourcing`, and `LiveLocationProvider`** — unit-tested
  through a mock (the suite above).
- **Risk monitoring (`RiskMonitor`, `RiskZone`, `proximity`)** — unit-tested with
  scripted coordinates fed through the mock source: enter/exit/approach
  transitions, no-spam-while-stationary, multi-zone independence, and the
  proximity distance itself.
- **`SystemLocationSource`** — compiled and type-checked as part of
  `swift build`/`swift test` under Swift 6 strict concurrency, but its live
  CoreLocation behavior is not unit-tested, since that needs a device.
- **The TypeScript surface (`src/`)** — type-checked and compiled to `build/`
  with `npm run build` (`tsc`, strict). Run it to verify the JS surface.
- **The Expo Swift adapter (`ios/`)** — written against verified Expo SDK 56 APIs;
  it is not compiled in this repository on its own, since it builds only as part
  of an app that installs `ExpoModulesCore`. Build the example app to compile it.

## Running the example

The `example/` directory is a self-contained Expo app that consumes the module
via Expo autolinking (`expo.autolinking.nativeModulesDir: ".."`).

```bash
npm install && npm run build      # build the module's JS surface to build/
cd example
npm install
npx expo run:ios                  # prebuilds, pod installs, and launches on iOS
```

`npx expo run:ios` requires a full Xcode install (not just the Command Line
Tools). The example app declares `NSLocationWhenInUseUsageDescription`, so iOS
will prompt for permission on first launch.

The example monitors three demo risk zones around the simulator's default San
Francisco location and shows the live banner pictured above, which changes as the
simulated location enters, approaches, and leaves a zone. A freshly launched
simulator sits inside one zone, so the banner shows **Inside risk zone** on the
first fix with no setup.

To watch the banner transition through every state, drive the bundled
`example/route.gpx` through the zones (**Xcode ▸ Debug ▸ Simulate Location ▸ Add
GPX File to Workspace…**, then pick `route`). Without Xcode, move a booted
simulator along the same path from the command line:

```bash
# Jump to a single state:
xcrun simctl location booted set 37.7858,-122.4064    # Inside      (red)
xcrun simctl location booted set 37.7896,-122.4103    # Approaching (amber)
xcrun simctl location booted set 37.7780,-122.3920    # All clear   (green)

# Drive the whole Inside → clear → Approaching → Inside → clear loop:
xcrun simctl location booted start --speed=12 \
  37.785800,-122.406400 37.789573,-122.410152 37.792088,-122.412653 \
  37.794603,-122.415154
```

## Requirements

- iOS 16+
- Expo SDK 56+

## License

MIT — see [LICENSE](./LICENSE).
