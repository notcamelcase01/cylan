import 'dart:async';

import 'package:cylan/core/api/api_client.dart';
import 'package:cylan/core/api/api_exception.dart';
import 'package:cylan/core/models/ride.dart';
import 'package:cylan/features/rides/providers/suggested_rides_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake, same `noSuchMethod` shape as `rides_provider_test.dart`'s
/// `_FakeApi` — this provider only ever calls `listRides` and `unsuggestRide`.
class _FakeApi implements ApiClient {
  final List<Completer<RidePage>> pending = [];
  bool? lastSuggested;

  @override
  Future<RidePage> listRides({String? pageUrl, String? search, bool? suggested}) {
    lastSuggested = suggested;
    final completer = Completer<RidePage>();
    pending.add(completer);
    return completer.future;
  }

  /// What `unsuggestRide` does next: succeed, or throw the given [Object].
  Object? unsuggestResult;
  int? lastUnsuggestedId;

  @override
  Future<void> unsuggestRide(int rideId) async {
    lastUnsuggestedId = rideId;
    final result = unsuggestResult;
    if (result == null) return;
    throw result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Ride _ride(int id, String name, {String status = 'PENDING'}) => Ride(
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
      publicSuggestionStatus: status,
    );

RidePage _page(List<Ride> results, {String? next}) => RidePage(
      count: results.length,
      next: next,
      previous: null,
      results: results,
    );

void main() {
  test('loadFirst asks the API for suggested=true', () async {
    final api = _FakeApi();
    final provider = SuggestedRidesProvider(api: api);

    final loaded = provider.loadFirst();
    api.pending[0].complete(_page([_ride(1, 'Sunday loop')]));
    await loaded;

    expect(api.lastSuggested, isTrue);
    expect(provider.rides.single.name, 'Sunday loop');
  });

  test('a successful unsuggest removes the ride from the list', () async {
    final api = _FakeApi();
    final provider = SuggestedRidesProvider(api: api);

    final loaded = provider.loadFirst();
    api.pending[0].complete(_page([_ride(1, 'a'), _ride(2, 'b')]));
    await loaded;

    final ok = await provider.unsuggest(1);

    expect(ok, isTrue);
    expect(api.lastUnsuggestedId, 1);
    expect(provider.rides.map((r) => r.name), ['b']);
  });

  test('a failed unsuggest leaves the list untouched and surfaces the error',
      () async {
    final api = _FakeApi()..unsuggestResult = ApiException('Something went wrong.');
    final provider = SuggestedRidesProvider(api: api);

    final loaded = provider.loadFirst();
    api.pending[0].complete(_page([_ride(1, 'a')]));
    await loaded;

    final ok = await provider.unsuggest(1);

    expect(ok, isFalse);
    expect(provider.error, 'Something went wrong.');
    expect(provider.rides.map((r) => r.name), ['a']);
  });

  test('an unexpected 200 body is caught, not left to crash the caller',
      () async {
    final api = _FakeApi();
    final provider = SuggestedRidesProvider(api: api);

    final loaded = provider.loadFirst();
    api.pending[0].completeError(StateError('unexpected shape'));
    await loaded;

    expect(provider.error, "Couldn't load your public suggestions.");
    expect(provider.rides, isEmpty);
  });
}
