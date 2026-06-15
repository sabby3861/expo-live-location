import { useLiveLocation, type RiskAlert, type RiskZone } from 'expo-live-location';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef } from 'react';
import {
  Animated,
  Platform,
  StyleSheet,
  Text,
  useColorScheme,
  View,
  type ColorValue,
} from 'react-native';

/**
 * Demo risk zones around the iOS Simulator's default location
 * (37.7858, -122.4064, in San Francisco's SoMa). They are spaced so a freshly
 * launched simulator sits inside exactly one zone — the banner shows INSIDE the
 * moment the first fix lands, with no setup.
 *
 * To watch the banner transition live, drive the bundled `route.gpx` through the
 * zones (Xcode ▸ Debug ▸ Simulate Location ▸ Add GPX File), or against a booted
 * simulator with no Xcode:
 *
 *   # Jump to a single state:
 *   xcrun simctl location booted set 37.7858,-122.4064    # INSIDE  (red)
 *   xcrun simctl location booted set 37.7896,-122.4103    # APPROACHING (amber)
 *   xcrun simctl location booted set 37.7780,-122.3920    # SAFE    (green)
 *
 *   # Drive the whole INSIDE → clear → APPROACHING → INSIDE → clear loop:
 *   xcrun simctl location booted start --speed=12 \
 *     37.785800,-122.406400 37.789573,-122.410152 37.792088,-122.412653 \
 *     37.794603,-122.415154
 */
const DEMO_ZONES: RiskZone[] = [
  { name: 'Yerba Buena Gardens', latitude: 37.7858, longitude: -122.4064, radius: 250 },
  { name: 'Civic Center', latitude: 37.792088, longitude: -122.412653, radius: 250 },
  { name: 'Mission Bay', latitude: 37.775919, longitude: -122.416064, radius: 300 },
];

/** A system monospaced face so coordinates keep a fixed width as they update. */
const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' });

type Scheme = 'light' | 'dark';

/** A single resolved color theme. Kept flat so styles read as `palette.x`. */
type Palette = {
  background: string;
  card: string;
  cardBorder: string;
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  accent: string;
  shadowOpacity: number;
};

const PALETTES: Record<Scheme, Palette> = {
  light: {
    background: '#F2F3F7',
    card: '#FFFFFF',
    cardBorder: '#ECECF0',
    textPrimary: '#16181D',
    textSecondary: '#5B626E',
    textMuted: '#6E747F',
    accent: '#2F6BFF',
    shadowOpacity: 0.1,
  },
  dark: {
    background: '#0B0E14',
    card: '#161B23',
    cardBorder: '#232A35',
    textPrimary: '#F0F3F8',
    textSecondary: '#9BA5B3',
    textMuted: '#868F9C',
    accent: '#6C9BFF',
    shadowOpacity: 0.45,
  },
};

/** The three states the hero banner can show, in escalation order. */
type RiskState = 'safe' | 'approaching' | 'inside';

const STATE_ORDER: RiskState[] = ['safe', 'approaching', 'inside'];
const STATE_INDEX: Record<RiskState, number> = { safe: 0, approaching: 1, inside: 2 };

/** A tinted background plus the strong accent used for a risk state's icon/title. */
type RiskColor = { tint: string; strong: string };

const RISK_COLORS: Record<Scheme, Record<RiskState, RiskColor>> = {
  light: {
    safe: { tint: '#E6F4EA', strong: '#1E8E3E' },
    approaching: { tint: '#FEF1DC', strong: '#B26A00' },
    inside: { tint: '#FCE8E6', strong: '#C5221F' },
  },
  dark: {
    safe: { tint: '#11251A', strong: '#5BD68B' },
    approaching: { tint: '#2A2210', strong: '#F4B740' },
    inside: { tint: '#2C1514', strong: '#FF6B66' },
  },
};

/** A non-emoji glyph per state — renders identically everywhere, unlike emoji. */
const GLYPH: Record<RiskState, string> = { safe: '✓', approaching: '▲', inside: '⚠' };

/** Collapses a risk alert (or its absence) to one of the banner's three states. */
function deriveState(risk: RiskAlert | null): RiskState {
  switch (risk?.kind) {
    case 'entered':
      return 'inside';
    case 'approaching':
      return 'approaching';
    default:
      // `exited` and "no alert yet" are both the all-clear state.
      return 'safe';
  }
}

/** Human-readable copy for the banner: a headline, a sub-line, and a VoiceOver label. */
function describe(state: RiskState, risk: RiskAlert | null): {
  title: string;
  subtitle: string;
  a11y: string;
} {
  const distance = risk ? Math.round(risk.distance) : 0;
  switch (state) {
    case 'inside':
      return {
        title: 'Inside risk zone',
        subtitle: `${risk?.zone ?? 'Zone'} · ${distance} m from center`,
        a11y: `Alert: inside ${risk?.zone ?? 'a risk zone'}, ${distance} meters from center.`,
      };
    case 'approaching':
      return {
        title: 'Approaching zone',
        subtitle: `${risk?.zone ?? 'Zone'} · ${distance} m away`,
        a11y: `Warning: approaching ${risk?.zone ?? 'a risk zone'}, ${distance} meters away.`,
      };
    default:
      return {
        title: 'All clear',
        subtitle: risk?.kind === 'exited' ? `Left ${risk.zone} — you're clear` : 'No risk zones nearby',
        a11y: risk?.kind === 'exited' ? `Clear. Left ${risk.zone}.` : 'All clear. No risk zones nearby.',
      };
  }
}

/**
 * The hero element: a single banner whose tint and accent morph between the
 * safe / approaching / inside states. The morph is driven by an `Animated.Value`
 * tracking the state index, so adjacent transitions glide through the color
 * range instead of snapping; the icon springs on each change to draw the eye.
 */
function RiskBanner({
  state,
  risk,
  palette,
  scheme,
}: {
  state: RiskState;
  risk: RiskAlert | null;
  palette: Palette;
  scheme: Scheme;
}) {
  const index = STATE_INDEX[state];
  // First render is always `safe` (the first risk event lands just after mount),
  // so the opening fix eases the banner into its real state rather than snapping.
  const progress = useRef(new Animated.Value(index)).current;
  const pop = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    Animated.timing(progress, {
      toValue: index,
      duration: 380,
      useNativeDriver: false, // color interpolation is not native-driver eligible
    }).start();
    pop.setValue(0.8);
    Animated.spring(pop, { toValue: 1, friction: 5, tension: 90, useNativeDriver: true }).start();
  }, [index, progress, pop]);

  const colors = RISK_COLORS[scheme];
  const inputRange = [0, 1, 2];
  const background = progress.interpolate({
    inputRange,
    outputRange: STATE_ORDER.map((s) => colors[s].tint),
  });
  const strong = progress.interpolate({
    inputRange,
    outputRange: STATE_ORDER.map((s) => colors[s].strong),
  });
  const copy = describe(state, risk);

  return (
    <Animated.View
      accessibilityRole="summary"
      accessibilityLabel={copy.a11y}
      style={[styles.banner, shadow(palette), { backgroundColor: background }]}>
      <Animated.View style={[styles.bannerIconWrap, { transform: [{ scale: pop }] }]}>
        <Animated.Text style={[styles.bannerIcon, { color: strong }]}>{GLYPH[state]}</Animated.Text>
      </Animated.View>
      <View style={styles.bannerText}>
        <Animated.Text style={[styles.bannerTitle, { color: strong }]}>{copy.title}</Animated.Text>
        <Text style={[styles.bannerSubtitle, { color: palette.textSecondary }]}>{copy.subtitle}</Text>
      </View>
    </Animated.View>
  );
}

/** A small radar-style dot whose ring keeps pulsing while updates stream in. */
function TrackingPulse({ color }: { color: ColorValue }) {
  const pulse = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(pulse, { toValue: 1, duration: 1600, useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  const scale = pulse.interpolate({ inputRange: [0, 1], outputRange: [1, 2.8] });
  const opacity = pulse.interpolate({ inputRange: [0, 1], outputRange: [0.5, 0] });

  return (
    <View style={styles.pulseWrap}>
      <Animated.View
        style={[styles.pulseRing, { backgroundColor: color, opacity, transform: [{ scale }] }]}
      />
      <View style={[styles.pulseDot, { backgroundColor: color }]} />
    </View>
  );
}

/** A captioned, monospaced value cell used for coordinates and the stats row. */
function Field({
  caption,
  value,
  palette,
  emphasis,
}: {
  caption: string;
  value: string;
  palette: Palette;
  emphasis?: boolean;
}) {
  return (
    <View style={styles.field}>
      <Text style={[styles.fieldCaption, { color: palette.textMuted }]}>{caption}</Text>
      <Text
        style={[
          emphasis ? styles.fieldValueLarge : styles.fieldValue,
          { color: palette.textPrimary },
        ]}>
        {value}
      </Text>
    </View>
  );
}

/** The live-location card: prominent coordinates, a stats row, and a timestamp. */
function LocationCard({
  location,
  palette,
}: {
  location: NonNullable<ReturnType<typeof useLiveLocation>['location']>;
  palette: Palette;
}) {
  const speed = location.speed < 0 ? '—' : `${location.speed.toFixed(1)} m/s`;
  return (
    <View style={[styles.card, shadow(palette), { backgroundColor: palette.card, borderColor: palette.cardBorder }]}>
      <View style={styles.cardHeader}>
        <Text style={[styles.cardEyebrow, { color: palette.textMuted }]}>LIVE LOCATION</Text>
        <View style={styles.trackingRow}>
          <TrackingPulse color={palette.accent} />
          <Text style={[styles.trackingLabel, { color: palette.accent }]}>Tracking</Text>
        </View>
      </View>

      <View style={styles.coordsRow}>
        <Field caption="LATITUDE" value={location.latitude.toFixed(6)} palette={palette} emphasis />
        <Field caption="LONGITUDE" value={location.longitude.toFixed(6)} palette={palette} emphasis />
      </View>

      <View style={[styles.statsRow, { borderTopColor: palette.cardBorder }]}>
        <Field caption="ALTITUDE" value={`${location.altitude.toFixed(0)} m`} palette={palette} />
        <Field caption="SPEED" value={speed} palette={palette} />
        <Field caption="ACCURACY" value={`±${location.horizontalAccuracy.toFixed(0)} m`} palette={palette} />
      </View>

      <Text style={[styles.timestamp, { color: palette.textMuted }]}>
        Updated {new Date(location.timestamp).toLocaleTimeString()}
      </Text>
    </View>
  );
}

/** A muted placeholder card shown after permission is granted, before the first fix. */
function WaitingCard({ palette }: { palette: Palette }) {
  return (
    <View style={[styles.card, shadow(palette), { backgroundColor: palette.card, borderColor: palette.cardBorder }]}>
      <View style={styles.trackingRow}>
        <TrackingPulse color={palette.accent} />
        <Text style={[styles.waitingText, { color: palette.textSecondary }]}>Waiting for first fix…</Text>
      </View>
    </View>
  );
}

/** A status pill summarizing the location permission, with a matching dot color. */
function PermissionPill({
  permission,
  palette,
  scheme,
}: {
  permission: ReturnType<typeof useLiveLocation>['permission'];
  palette: Palette;
  scheme: Scheme;
}) {
  const risk = RISK_COLORS[scheme];
  const { dot, label } =
    permission === 'granted'
      ? { dot: risk.safe.strong, label: 'Location on' }
      : permission === 'denied'
        ? { dot: risk.inside.strong, label: 'Location denied' }
        : { dot: palette.textMuted, label: 'Requesting…' };

  return (
    <View style={[styles.pill, { backgroundColor: palette.card, borderColor: palette.cardBorder }]}>
      <View style={[styles.pillDot, { backgroundColor: dot }]} />
      <Text style={[styles.pillLabel, { color: palette.textSecondary }]}>{label}</Text>
    </View>
  );
}

/**
 * Example screen for expo-live-location.
 *
 * `useLiveLocation(...)` does all the work: it requests permission on mount,
 * starts the native stream, monitors the demo risk zones, and tears everything
 * down on unmount. This screen is presentation only — it maps the hook's output
 * to a calm, light/dark-aware UI with the risk banner as the hero element.
 */
export default function App() {
  const scheme: Scheme = useColorScheme() === 'dark' ? 'dark' : 'light';
  const palette = PALETTES[scheme];
  const { location, permission, error, risk } = useLiveLocation({ riskZones: DEMO_ZONES });
  const state = deriveState(risk);

  return (
    <View style={[styles.container, { backgroundColor: palette.background }]}>
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />

      <View style={styles.header}>
        <View style={styles.headerText}>
          <Text style={[styles.title, { color: palette.textPrimary }]}>Live Location</Text>
          <Text style={[styles.subtitle, { color: palette.textSecondary }]}>Real-time safety monitor</Text>
        </View>
        <PermissionPill permission={permission} palette={palette} scheme={scheme} />
      </View>

      <RiskBanner state={state} risk={risk} palette={palette} scheme={scheme} />

      {error ? (
        <View style={[styles.card, shadow(palette), { backgroundColor: palette.card, borderColor: palette.cardBorder }]}>
          <Text style={[styles.cardEyebrow, { color: RISK_COLORS[scheme].inside.strong }]}>ERROR</Text>
          <Text style={[styles.errorText, { color: palette.textPrimary }]}>{error.message}</Text>
        </View>
      ) : location ? (
        <LocationCard location={location} palette={palette} />
      ) : permission === 'granted' ? (
        <WaitingCard palette={palette} />
      ) : permission === 'denied' ? (
        <View style={[styles.card, shadow(palette), { backgroundColor: palette.card, borderColor: palette.cardBorder }]}>
          <Text style={[styles.waitingText, { color: palette.textSecondary }]}>
            Location access is off. Enable it in Settings to see live updates.
          </Text>
        </View>
      ) : null}
    </View>
  );
}

/** Shared soft-shadow style, tuned per scheme (deeper but darker in dark mode). */
function shadow(palette: Palette) {
  return {
    shadowColor: '#000000',
    shadowOpacity: palette.shadowOpacity,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 10 },
    elevation: 5,
  };
}

const styles = StyleSheet.create({
  container: { flex: 1, paddingHorizontal: 20, paddingTop: 76, gap: 18 },

  header: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' },
  headerText: { flexShrink: 1, paddingRight: 12 },
  title: { fontSize: 34, fontWeight: '800', letterSpacing: -0.5 },
  subtitle: { fontSize: 15, marginTop: 2 },

  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
  },
  pillDot: { width: 8, height: 8, borderRadius: 4 },
  pillLabel: { fontSize: 13, fontWeight: '600' },

  banner: { flexDirection: 'row', alignItems: 'center', gap: 14, padding: 18, borderRadius: 22 },
  bannerIconWrap: { width: 30, alignItems: 'center' },
  bannerIcon: { fontSize: 26, fontWeight: '700' },
  bannerText: { flex: 1 },
  bannerTitle: { fontSize: 19, fontWeight: '700', letterSpacing: -0.2 },
  bannerSubtitle: { fontSize: 14, marginTop: 2, fontVariant: ['tabular-nums'] },

  card: { padding: 20, borderRadius: 22, borderWidth: StyleSheet.hairlineWidth, gap: 16 },
  cardHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  cardEyebrow: { fontSize: 12, fontWeight: '700', letterSpacing: 1 },

  trackingRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  trackingLabel: { fontSize: 13, fontWeight: '600' },

  coordsRow: { flexDirection: 'row', gap: 16 },
  statsRow: { flexDirection: 'row', justifyContent: 'space-between', gap: 12, paddingTop: 14, borderTopWidth: StyleSheet.hairlineWidth },

  field: { flex: 1, gap: 4 },
  fieldCaption: { fontSize: 11, fontWeight: '700', letterSpacing: 0.8 },
  fieldValue: { fontFamily: MONO, fontSize: 15, fontVariant: ['tabular-nums'] },
  fieldValueLarge: { fontFamily: MONO, fontSize: 22, fontWeight: '600', fontVariant: ['tabular-nums'] },

  timestamp: { fontSize: 13, fontVariant: ['tabular-nums'] },

  pulseWrap: { width: 12, height: 12, alignItems: 'center', justifyContent: 'center' },
  pulseRing: { position: 'absolute', width: 12, height: 12, borderRadius: 6 },
  pulseDot: { width: 8, height: 8, borderRadius: 4 },

  waitingText: { fontSize: 15 },
  errorText: { fontSize: 15, lineHeight: 21 },
});
