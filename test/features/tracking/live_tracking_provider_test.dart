import 'dart:async';

import 'package:cylan/core/models/ride.dart';
import 'package:cylan/core/models/ride_profile.dart';
import 'package:cylan/features/tracking/providers/live_tracking_provider.dart';
import 'package:cylan/features/tracking/services/location_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// A [LocationService] whose `ensureReady` is settled by hand, standing in for
/// the OS permission prompt — which the rider can leave open for as long as
/// they like, and walk away from. [positions] is the feed itself, so a test can
/// push a fix, an error, or nothing at all.
class _FakeLocationService implements LocationService {
  final ready = Completer<void>();
  final positions = StreamController<Position>.broadcast();

  /// How many times a caller actually subscribed. The leak this guards against
  /// is a subscription opened *after* dispose, which nothing then cancels.
  int subscribeCount = 0;

  @override
  Future<void> ensureReady() => ready.future;

  @override
  Stream<Position> positionStream() {
    subscribeCount++;
    return positions.stream;
  }
}

Ride _ride() => Ride(
      id: 1,
      name: 'Test',
      sourceFormat: 'gpx',
      recordedAt: null,
      createdAt: DateTime(2026, 1, 1),
      distanceKm: 10,
      distanceM: 10000,
      totalAscentM: 0,
      totalDescentM: 0,
      minElevationM: 0,
      maxElevationM: 0,
      netElevationM: 0,
      maxGradientPct: 0,
      minGradientPct: 0,
      pointCount: 2,
      profile: RideProfile(
        distanceKm: const [0, 1],
        elevationM: const [0, 10],
        gradientPct: const [0, 1],
        latitude: const [12.9, 12.91],
        longitude: const [77.5, 77.51],
      ),
    );

Position _position() => Position(
      latitude: 12.9,
      longitude: 77.5,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('leaving while the permission prompt is open never opens the GPS feed',
      () async {
    final location = _FakeLocationService();
    final provider = LiveTrackingProvider(_ride(), locationService: location);

    provider.start(); // parks on ensureReady, as it would on the OS prompt

    // The rider backs out while the prompt is still up.
    provider.dispose();

    // Only now does the prompt resolve.
    location.ready.complete();
    await Future<void>.delayed(Duration.zero);

    expect(location.subscribeCount, 0,
        reason: 'subscribing after dispose opens a position stream that '
            'nothing will ever cancel — the receiver stays awake, draining the '
            'battery, for the rest of the process');
    expect(location.positions.hasListener, isFalse);
  });

  test('a failure to start surfaces an error rather than spinning forever',
      () async {
    final location = _FakeLocationService();
    final provider = LiveTrackingProvider(_ride(), locationService: location);

    final started = provider.start();
    // Not a LocationPermissionDenied — e.g. a geolocator PlatformException.
    location.ready.completeError(Exception('receiver exploded'));
    await started;

    expect(provider.isLoading, isFalse,
        reason: 'isLoading left true is a spinner the rider cannot get past, '
            'on the one screen they are using mid-ride');
    expect(provider.error, isNotNull);
  });

  test('a permission refusal explains itself and stops', () async {
    final location = _FakeLocationService();
    final provider = LiveTrackingProvider(_ride(), locationService: location);

    final started = provider.start();
    location.ready.completeError(LocationPermissionDenied('Nope.'));
    await started;

    expect(provider.permissionMessage, 'Nope.');
    expect(provider.isLoading, isFalse);
    expect(location.subscribeCount, 0);
  });

  test('a feed error is a note, not a screen replacement', () async {
    final location = _FakeLocationService();
    final provider = LiveTrackingProvider(_ride(), locationService: location);

    final started = provider.start();
    location.ready.complete();
    await started;

    location.positions.addError(Exception('signal lost'));
    await Future<void>.delayed(Duration.zero);

    expect(provider.gpsMessage, isNotNull);
    expect(provider.error, isNull,
        reason: 'error replaces the whole screen — losing the route because '
            'the signal dipped would be wildly disproportionate');
  });

  test('a fix clears the note', () async {
    final location = _FakeLocationService();
    final provider = LiveTrackingProvider(_ride(), locationService: location);

    final started = provider.start();
    location.ready.complete();
    await started;

    location.positions.addError(Exception('signal lost'));
    await Future<void>.delayed(Duration.zero);
    expect(provider.gpsMessage, isNotNull);

    location.positions.add(_position());
    await Future<void>.delayed(Duration.zero);

    expect(provider.gpsMessage, isNull);
    expect(provider.position, isNotNull);
  });

  test('a fix that never arrives says so instead of staying silent', () {
    fakeAsync((async) {
      final location = _FakeLocationService();
      final provider = LiveTrackingProvider(_ride(), locationService: location);

      provider.start();
      location.ready.complete();
      async.flushMicrotasks();

      expect(provider.gpsMessage, isNull, reason: 'still within the grace');

      // Core Location can fail to get a fix without reporting anything to us
      // (geolocator swallows kCLErrorLocationUnknown), so nothing arrives at
      // all — which is exactly the silent case this covers.
      async.elapse(const Duration(seconds: 11));

      expect(provider.gpsMessage, isNotNull,
          reason: 'a dot that never appears, with nothing on screen to say '
              'whether it is still trying, is the worst of both worlds');
    });
  });
}
