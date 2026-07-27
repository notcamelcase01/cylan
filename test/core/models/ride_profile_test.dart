import 'package:cylan/core/models/ride_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// A straight 4 km line east along the equator-ish, one sample per km, so
/// interpolation results are easy to reason about.
RideProfile _profile() => RideProfile(
      distanceKm: const [0, 1, 2, 3, 4],
      elevationM: const [0, 10, 20, 30, 40],
      gradientPct: const [0, 1, 2, 3, 4],
      latitude: const [12.0, 12.0, 12.0, 12.0, 12.0],
      longitude: const [77.0, 77.01, 77.02, 77.03, 77.04],
    );

void main() {
  group('pointAtKm', () {
    test('returns the sample sitting exactly on a distance', () {
      expect(_profile().pointAtKm(2).longitude, closeTo(77.02, 1e-9));
    });

    test('interpolates between two samples', () {
      // Halfway between km 1 and km 2 is halfway between their longitudes.
      expect(_profile().pointAtKm(1.5).longitude, closeTo(77.015, 1e-9));
    });

    test('clamps a distance before the start to the first point', () {
      expect(_profile().pointAtKm(-5).longitude, closeTo(77.0, 1e-9));
    });

    test('clamps a distance past the end to the last point', () {
      expect(_profile().pointAtKm(99).longitude, closeTo(77.04, 1e-9));
    });
  });

  group('nearestDistanceKm', () {
    test('finds the distance of the closest sample', () {
      expect(_profile().nearestDistanceKm(const LatLng(12.0, 77.03)), 3);
    });

    test('snaps an off-route point to the nearest sample', () {
      // Well north of the line, but nearest km 1 along it.
      expect(_profile().nearestDistanceKm(const LatLng(12.5, 77.0102)), 1);
    });

    test('round-trips with pointAtKm', () {
      final profile = _profile();
      expect(profile.nearestDistanceKm(profile.pointAtKm(3)), 3);
    });
  });

  group('empty profile', () {
    final empty = RideProfile(
      distanceKm: const [],
      elevationM: const [],
      gradientPct: const [],
      latitude: const [],
      longitude: const [],
    );

    test('reports no track', () => expect(empty.hasTrack, isFalse));
    test('has zero total', () => expect(empty.totalKm, 0));
    test('nearestDistanceKm does not throw', () {
      expect(empty.nearestDistanceKm(const LatLng(12, 77)), 0);
    });
  });

  test('totalKm is the last sampled distance', () {
    expect(_profile().totalKm, 4);
  });
}
