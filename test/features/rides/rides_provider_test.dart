import 'dart:async';

import 'package:cylan/core/api/api_client.dart';
import 'package:cylan/core/api/api_exception.dart';
import 'package:cylan/core/models/ride.dart';
import 'package:cylan/features/rides/providers/rides_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [ApiClient] whose `listRides` never resolves on its own — each call parks
/// a [Completer] in [pending] for the test to settle by hand, in whatever order
/// it likes. That hand-ordering is the whole point: these are races between two
/// in-flight requests, so a fake that just returns a value can't reach them.
///
/// `noSuchMethod` covers the other ~24 endpoints, which throw loudly if this
/// ever touches one it shouldn't.
class _FakeApi implements ApiClient {
  final List<Completer<RidePage>> pending = [];

  /// The `pageUrl` each call asked for — `null` for page 1. Lets a test prove
  /// *which* page a later request continues from.
  final List<String?> calls = [];

  @override
  Future<RidePage> listRides({String? pageUrl}) {
    calls.add(pageUrl);
    final completer = Completer<RidePage>();
    pending.add(completer);
    return completer.future;
  }

  /// What `importFromGoogleMaps` does next: a [Ride] to succeed with, or any
  /// [Object] to throw — lets a test drive both an [ApiException] (a domain
  /// error the server sent) and an arbitrary failure (the "something we
  /// never anticipated" case [RidesProvider] must still catch).
  Object? googleMapsResult;

  @override
  Future<Ride> importFromGoogleMaps({required String url, String? name}) async {
    final result = googleMapsResult;
    if (result is Ride) return result;
    throw result ?? StateError('googleMapsResult not set for this test');
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

RidePage _page(List<Ride> results, {String? next}) => RidePage(
      count: results.length,
      next: next,
      previous: null,
      results: results,
    );

Iterable<String> _names(RidesProvider p) => p.rides.map((r) => r.name);

void main() {
  group('RidesProvider request races', () {
    test('a loadMore landing after a refresh is discarded, not appended',
        () async {
      final api = _FakeApi();
      final provider = RidesProvider(api: api);

      final initial = provider.loadFirst();
      api.pending[0].complete(_page([_ride(1, 'a'), _ride(2, 'b')], next: 'page2'));
      await initial;
      expect(_names(provider), ['a', 'b']);

      // The rider scrolls to the bottom: page 2 goes out...
      final more = provider.loadMore();
      expect(api.calls.last, 'page2');

      // ...and they pull to refresh before it lands.
      final refresh = provider.refresh();

      // The refresh wins the race, rebuilding the list from newer server state.
      api.pending[2].complete(_page([_ride(9, 'fresh')], next: 'page2-fresh'));
      await refresh;

      // Only now does the abandoned page 2 arrive.
      api.pending[1].complete(_page([_ride(3, 'stale')], next: 'page3-stale'));
      await more;

      expect(_names(provider), ['fresh'],
          reason: 'page 2 of the list that no longer exists must not be '
              'spliced onto the refreshed one');

      // And the cursor must still continue the fresh list, not the old one.
      provider.loadMore();
      expect(api.calls.last, 'page2-fresh',
          reason: 'the stale response must not have moved the page cursor');
    });

    test('two overlapping refreshes settle on the newer answer', () async {
      final api = _FakeApi();
      final provider = RidesProvider(api: api);

      final older = provider.loadFirst();
      final newer = provider.loadFirst();

      api.pending[1].complete(_page([_ride(2, 'newer')]));
      await newer;

      // The older refresh lands last, carrying an answer already out of date.
      api.pending[0].complete(_page([_ride(1, 'older')]));
      await older;

      expect(_names(provider), ['newer'],
          reason: 'last-to-land must not beat most-recently-asked');
      expect(provider.isLoading, isFalse);
    });

    test('a superseded load leaves the newer one spinner alone', () async {
      final api = _FakeApi();
      final provider = RidesProvider(api: api);

      final older = provider.loadFirst();
      final newer = provider.loadFirst();

      api.pending[0].complete(_page([_ride(1, 'older')]));
      await older;
      expect(provider.isLoading, isTrue,
          reason: 'the newer load is still in flight and owns the flag');

      api.pending[1].complete(_page([_ride(2, 'newer')]));
      await newer;
      expect(provider.isLoading, isFalse);
    });

    test('a failure from a superseded load is not shown to the rider', () async {
      final api = _FakeApi();
      final provider = RidesProvider(api: api);

      final older = provider.loadFirst();
      final newer = provider.loadFirst();

      api.pending[1].complete(_page([_ride(1, 'ok')]));
      await newer;

      api.pending[0].completeError(ApiException('stale failure'));
      await older;

      expect(provider.error, isNull,
          reason: 'an error belonging to an abandoned request would be a '
              'phantom: the list on screen loaded fine');
      expect(_names(provider), ['ok']);
    });
  });

  group('Google Maps import', () {
    test('a successful import prepends the new ride and clears any error',
        () async {
      final api = _FakeApi()..googleMapsResult = _ride(5, 'Sunday loop');
      final provider = RidesProvider(api: api);

      final ride = await provider
          .importFromGoogleMaps(url: 'https://maps.app.goo.gl/x');

      expect(ride?.name, 'Sunday loop');
      expect(provider.error, isNull);
      expect(_names(provider), ['Sunday loop']);
    });

    test('a domain error (route outside India) surfaces its message, not a '
        'crash', () async {
      final api = _FakeApi()
        ..googleMapsResult = ApiException(
            "This route goes outside India, which isn't supported for "
            'Google Maps import yet.');
      final provider = RidesProvider(api: api);

      final ride = await provider
          .importFromGoogleMaps(url: 'https://maps.app.goo.gl/x');

      expect(ride, isNull);
      expect(provider.error, contains('outside India'));
      expect(_names(provider), isEmpty,
          reason: 'a failed import must not add a phantom ride to the list');
    });

    test('an unanticipated failure (not an ApiException) is still caught, '
        'never left to crash the caller or strand its busy flag', () async {
      final api = _FakeApi()..googleMapsResult = Exception('boom');
      final provider = RidesProvider(api: api);

      final ride = await provider
          .importFromGoogleMaps(url: 'https://maps.app.goo.gl/x');

      expect(ride, isNull);
      expect(provider.error, isNotNull);
    });
  });
}
