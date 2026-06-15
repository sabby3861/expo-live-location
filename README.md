# expo-live-location

Real-time iOS location for React Native, built the way a native SDK should be:
the device logic lives in a **pure Swift package** (`LiveLocationKit`) that has
zero dependency on Expo or React Native and exposes updates as a single
`AsyncStream<LocationSample>`. The Expo layer on top is a thin adapter — it
translates values across the JS bridge and gates the stream on listener
presence, and contains no location logic of its own. The result is a module that
is easy to reason about, fully typed end to end, and unit-tested without a
device or simulator.

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

The two mapping seams — `LocationSample ↔ CLLocation` and `LocationSample ↔ Expo
Record` — are the only places types are translated, and each lives in exactly
one file. CoreLocation is imported in exactly two files; Expo is imported only in
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
example/             Minimal example screen
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
- **`SystemLocationSource`** — compiled and type-checked as part of
  `swift build`/`swift test` under Swift 6 strict concurrency, but its live
  CoreLocation behavior is not unit-tested, since that needs a device.
- **The Expo adapter (`ios/`) and the TypeScript surface (`src/`)** — written
  against verified Expo SDK 56 APIs, but not built or type-checked on their own in
  this repository; they compile as part of a host app that installs the module's
  pods and JavaScript dependencies.

## Requirements

- iOS 16+
- Expo SDK 56+

## License

MIT — see [LICENSE](./LICENSE).
