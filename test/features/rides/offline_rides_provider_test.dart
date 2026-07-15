import 'dart:async';

import 'package:cylan/core/models/ride.dart';
import 'package:cylan/core/models/ride_section.dart';
import 'package:cylan/core/models/weather_point.dart';
import 'package:cylan/features/rides/providers/offline_rides_provider.dart';
import 'package:cylan/features/rides/services/offline_ride_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [OfflineRideStore] whose `list()` parks a [Completer] instead of reading
/// the disk, so a test can decide exactly when a read lands relative to a
/// write. `save`/`load` resolve immediately against an in-memory list, standing
/// in for the real documents directory (which doesn't exist under
/// `flutter test` anyway).
class _FakeStore implements OfflineRideStore {
  /// The completer for the most recent `list()` call.
  Completer<List<OfflineRide>>? pendingList;
  final List<OfflineRide> stored = [];

  @override
  Future<List<OfflineRide>> list() {
    final completer = Completer<List<OfflineRide>>();
    pendingList = completer;
    return completer.future;
  }

  @override
  Future<void> save(
    Ride ride,
    List<WeatherPoint> weather,
    List<RideSection> sections,
  ) async {
    stored.add(OfflineRide(
      ride: ride,
      weather: weather,
      sections: sections,
      savedAt: DateTime(2026, 1, 1),
    ));
  }

  @override
  Future<OfflineRide?> load(int id) async {
    for (final r in stored) {
      if (r.ride.id == id) return r;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Ride _ride(int id, String name) => Ride(
      id: id,
      name: name,
      sourceFormat: 'gpx',
      recordedAt: null,
      createdAt: DateTime(2026, 1, 1),
      distanceKm: 10,
      distanceM: 10000,
      totalAscentM: 100,
      totalDescentM: 100,
      minElevationM: 0,
      maxElevationM: 100,
      netElevationM: 0,
      maxGradientPct: 5,
      minGradientPct: -5,
      pointCount: 100,
    );

OfflineRide _offline(int id, String name) => OfflineRide(
      ride: _ride(id, name),
      weather: const [],
      sections: const [],
      savedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('OfflineRidesProvider read/write races', () {
    test('a save survives a refresh whose disk read predates it', () async {
      final store = _FakeStore();
      final provider = OfflineRidesProvider(store: store);

      // A refresh starts; its snapshot of the disk predates the save below.
      final refresh = provider.refresh();

      // The rider saves ride 42 while that read is still in flight.
      await provider.save(_ride(42, 'Alpine loop'), const [], const []);
      expect(provider.isSaved(42), isTrue);

      // Only now does the pre-save snapshot land — without ride 42 in it.
      store.pendingList!.complete([]);
      await refresh;

      expect(provider.isSaved(42), isTrue,
          reason: 'a read that predates the save must not erase it — the ride '
              'detail would flip back to unsaved with the data on disk');
      expect(provider.rides.map((r) => r.ride.id), [42],
          reason: 'the stale empty snapshot must not blank the list either');
      expect(provider.isLoading, isFalse,
          reason: 'an invalidated refresh must still release the spinner, or '
              'the offline screen spins forever');
    });

    test('two overlapping refreshes settle on the newer answer', () async {
      final store = _FakeStore();
      final provider = OfflineRidesProvider(store: store);

      final older = provider.refresh();
      final olderRead = store.pendingList!;
      final newer = provider.refresh();
      final newerRead = store.pendingList!;

      newerRead.complete([_offline(2, 'newer')]);
      await newer;

      // The older read lands last, carrying an already-outdated answer.
      olderRead.complete([_offline(1, 'older')]);
      await older;

      expect(provider.rides.map((r) => r.ride.id), [2],
          reason: 'last-to-land must not beat most-recently-asked');
      expect(provider.isLoading, isFalse);
    });
  });
}
