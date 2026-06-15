import { useLiveLocation } from 'expo-live-location';
import { StyleSheet, Text, View } from 'react-native';

/**
 * Minimal example screen.
 *
 * `useLiveLocation()` does all the work: it requests permission on mount, starts
 * the native stream, and tears everything down on unmount. The screen just
 * renders whatever the hook reports — permission state, the latest coordinate,
 * and a live-updating readout as the device moves.
 */
export default function App() {
  const { location, permission, error } = useLiveLocation();

  return (
    <View style={styles.container}>
      <Text style={styles.title}>expo-live-location</Text>
      <Text style={styles.row}>Permission: {permission ?? 'requesting…'}</Text>

      {error ? <Text style={styles.error}>{error.message}</Text> : null}

      {location ? (
        <View style={styles.card}>
          <Text style={styles.coord}>
            {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
          </Text>
          <Text style={styles.row}>Altitude: {location.altitude.toFixed(1)} m</Text>
          <Text style={styles.row}>
            Speed: {location.speed < 0 ? 'n/a' : `${location.speed.toFixed(1)} m/s`}
          </Text>
          <Text style={styles.row}>Accuracy: ±{location.horizontalAccuracy.toFixed(0)} m</Text>
          <Text style={styles.timestamp}>
            Updated {new Date(location.timestamp).toLocaleTimeString()}
          </Text>
        </View>
      ) : permission === 'granted' ? (
        <Text style={styles.row}>Waiting for first fix…</Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', padding: 24, gap: 8 },
  title: { fontSize: 22, fontWeight: '600', marginBottom: 8 },
  card: { marginTop: 12, padding: 16, borderRadius: 12, backgroundColor: '#f2f2f7', gap: 4 },
  coord: { fontSize: 20, fontVariant: ['tabular-nums'], fontWeight: '600' },
  row: { fontSize: 15, color: '#3a3a3c' },
  timestamp: { fontSize: 13, color: '#8e8e93', marginTop: 4 },
  error: { fontSize: 15, color: '#d70015' },
});
