import 'dart:math' as math;

import '../models/turn.dart';

/// Client-side turn detection, ported from the web app's `rides/geo.py`
/// (`detect_turns` / `bearing_deg` / `_turn_kind`). Live tracking runs
/// entirely on-device: turns are derived from the ride's stored profile
/// arrays, with no server round-trip while riding.

const double _turnThresholdDeg = 25.0;
const double _turnMergeDistanceM = 60.0;

double _bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final lat1r = _radians(lat1);
  final lat2r = _radians(lat2);
  final dLon = _radians(lon2 - lon1);
  final x = math.sin(dLon) * math.cos(lat2r);
  final y = math.cos(lat1r) * math.sin(lat2r) -
      math.sin(lat1r) * math.cos(lat2r) * math.cos(dLon);
  return (_degrees(math.atan2(x, y)) + 360.0) % 360.0;
}

String _turnKind(double angle) {
  final a = angle.abs();
  if (a >= 100) return 'sharp';
  if (a >= 45) return 'turn';
  return 'slight';
}

/// Finds turns along a route from consecutive-segment bearing changes.
///
/// Returns turns ordered by distance. `direction` is `"left"`/`"right"`;
/// `kind` is `slight` / `turn` / `sharp`. Nearby turns (within
/// [_turnMergeDistanceM]) are merged, keeping the sharpest.
List<Turn> detectTurns(
  List<double> latitudes,
  List<double> longitudes,
  List<double> distancesKm, {
  double thresholdDeg = _turnThresholdDeg,
  double mergeDistanceM = _turnMergeDistanceM,
}) {
  final n = math.min(
    latitudes.length,
    math.min(longitudes.length, distancesKm.length),
  );
  if (n < 3) return [];

  final raw = <Turn>[];
  for (var i = 1; i < n - 1; i++) {
    final b1 = _bearingDeg(
        latitudes[i - 1], longitudes[i - 1], latitudes[i], longitudes[i]);
    final b2 = _bearingDeg(
        latitudes[i], longitudes[i], latitudes[i + 1], longitudes[i + 1]);
    // Normalize to [-180, 180).
    final delta = (b2 - b1 + 180.0) % 360.0 - 180.0;
    if (delta.abs() < thresholdDeg) continue;
    raw.add(Turn(
      distanceKm: _round3(distancesKm[i]),
      direction: delta > 0 ? 'right' : 'left',
      kind: _turnKind(delta),
      angleDeg: _round1(delta.abs()),
    ));
  }

  // Merge turns closer than mergeDistanceM, keeping the sharpest angle.
  final merged = <Turn>[];
  final mergeKm = mergeDistanceM / 1000.0;
  for (final turn in raw) {
    if (merged.isNotEmpty &&
        (turn.distanceKm - merged.last.distanceKm) <= mergeKm) {
      if (turn.angleDeg > merged.last.angleDeg) {
        merged[merged.length - 1] = turn;
      }
      continue;
    }
    merged.add(turn);
  }
  return merged;
}

double _radians(double deg) => deg * math.pi / 180.0;
double _degrees(double rad) => rad * 180.0 / math.pi;
double _round3(double v) => (v * 1000).round() / 1000;
double _round1(double v) => (v * 10).round() / 10;
