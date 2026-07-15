import 'dart:async';

import 'package:cylan/core/api/api_client.dart';
import 'package:cylan/core/api/api_exception.dart';
import 'package:cylan/core/models/audax_event.dart';
import 'package:cylan/features/audax/providers/audax_events_cache_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [ApiClient] whose `listAudaxEvents` never resolves on its own — each call
/// parks a [Completer] in [pending] for the test to settle by hand, in whatever
/// order it likes. That hand-ordering is the whole point: these are races
/// between two in-flight requests, so a fake that just returns a value can't
/// reach them.
///
/// Mirrors `_FakeApi` in `rides_provider_test.dart`, because the guard under
/// test is the same one.
class _FakeApi implements ApiClient {
  final List<Completer<AudaxEventPage>> pending = [];

  /// The `pageUrl` each call asked for — null for page 1. Lets a test prove
  /// *which* page a later request continues from.
  final List<String?> calls = [];

  @override
  Future<AudaxEventPage> listAudaxEvents({
    String? pageUrl,
    int? month,
    int? year,
    bool? upcoming,
    String? city,
    String? state,
    String? category,
  }) {
    calls.add(pageUrl);
    final completer = Completer<AudaxEventPage>();
    pending.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AudaxEvent _event(String id) => AudaxEvent(
      audaxId: id,
      club: 'Club $id',
      audaxPageUrl: null,
      category: '200',
      registrationCloseDate: null,
      eventDate: DateTime(2026, 7, 1),
      startPoint: null,
      eventFee: null,
      clubContactNumber: null,
      routeMapUrl: null,
    );

AudaxEventPage _page(List<AudaxEvent> results, {String? next}) => AudaxEventPage(
      count: results.length,
      next: next,
      previous: null,
      results: results,
    );

const _key = 'k';

Future<void> _fetchFirst(
  AudaxEventsCacheProvider p, {
  bool force = false,
}) =>
    p.fetchFirst(_key, month: 7, year: 2026, upcomingOnly: false, force: force);

Iterable<String> _ids(AudaxEventsCacheProvider p) =>
    (p.eventsFor(_key) ?? const []).map((e) => e.audaxId);

void main() {
  group('AudaxEventsCacheProvider request races', () {
    test('a fetchMore landing after a refresh is discarded, not appended',
        () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      final initial = _fetchFirst(provider);
      api.pending[0].complete(_page([_event('a'), _event('b')], next: 'page2'));
      await initial;
      expect(_ids(provider), ['a', 'b']);

      // The rider scrolls to the bottom: page 2 goes out...
      final more = provider.fetchMore(_key);
      expect(api.calls.last, 'page2');

      // ...and they pull to refresh before it lands.
      final refresh = _fetchFirst(provider, force: true);

      // The refresh wins the race, rebuilding the list from newer server state.
      api.pending[2].complete(_page([_event('fresh')], next: 'page2-fresh'));
      await refresh;

      // Only now does the abandoned page 2 arrive.
      api.pending[1].complete(_page([_event('stale')], next: 'page3-stale'));
      await more;

      expect(_ids(provider), ['fresh'],
          reason: 'page 2 of the list that no longer exists must not be '
              'spliced onto the refreshed one');

      // And the cursor must still continue the fresh list, not the old one.
      provider.fetchMore(_key);
      expect(api.calls.last, 'page2-fresh',
          reason: 'the stale response must not have moved the page cursor');
    });

    test('two overlapping refreshes settle on the newer answer', () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      final older = _fetchFirst(provider, force: true);
      final newer = _fetchFirst(provider, force: true);

      api.pending[1].complete(_page([_event('newer')]));
      await newer;

      // The older refresh lands last, carrying an answer already out of date.
      api.pending[0].complete(_page([_event('older')]));
      await older;

      expect(_ids(provider), ['newer'],
          reason: 'last-to-land must not beat most-recently-asked');
      expect(provider.isLoadingFirst(_key), isFalse);
    });

    test('a superseded fetch leaves the newer one spinner alone', () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      final older = _fetchFirst(provider, force: true);
      final newer = _fetchFirst(provider, force: true);

      api.pending[0].complete(_page([_event('older')]));
      await older;
      expect(provider.isLoadingFirst(_key), isTrue,
          reason: 'the newer fetch is still in flight and owns the flag');

      api.pending[1].complete(_page([_event('newer')]));
      await newer;
      expect(provider.isLoadingFirst(_key), isFalse);
    });

    test('a failure from a superseded fetch is not shown to the rider',
        () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      final older = _fetchFirst(provider, force: true);
      final newer = _fetchFirst(provider, force: true);

      api.pending[1].complete(_page([_event('ok')]));
      await newer;

      api.pending[0].completeError(ApiException('stale failure'));
      await older;

      expect(provider.firstErrorFor(_key), isNull,
          reason: 'an error belonging to an abandoned request would be a '
              'phantom: the list on screen loaded fine');
      expect(_ids(provider), ['ok']);
    });

    test('one key\'s refresh does not invalidate another key\'s fetchMore',
        () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      // Two different months are two independent lists.
      final july = provider.fetchFirst('july',
          month: 7, year: 2026, upcomingOnly: false);
      api.pending[0].complete(_page([_event('j1')], next: 'july2'));
      await july;

      final august = provider.fetchFirst('august',
          month: 8, year: 2026, upcomingOnly: false);
      api.pending[1].complete(_page([_event('a1')], next: 'august2'));
      await august;

      // July loads more, then August refreshes while it's in flight.
      final julyMore = provider.fetchMore('july');
      final augustRefresh = provider.fetchFirst('august',
          month: 8, year: 2026, upcomingOnly: false, force: true);
      api.pending[3].complete(_page([_event('a-fresh')]));
      await augustRefresh;

      api.pending[2].complete(_page([_event('j2')]));
      await julyMore;

      expect((provider.eventsFor('july') ?? []).map((e) => e.audaxId),
          ['j1', 'j2'],
          reason: "a refresh of another month must not discard july's page 2");
    });
  });

  group('AudaxEventsCacheProvider unexpected failures', () {
    test('a non-ApiException surfaces as an error, not a stuck spinner',
        () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      final fetch = _fetchFirst(provider);
      // What a 200 whose body isn't the expected shape actually throws.
      api.pending[0].completeError(TypeError());
      await fetch;

      expect(provider.isLoadingFirst(_key), isFalse);
      expect(provider.eventsFor(_key), isNull);
      expect(provider.firstErrorFor(_key), isNotNull,
          reason: 'with no error set the screen falls through to its "fetch '
              'has not started yet" branch — a spinner with no retry');
    });

    test('a non-ApiException from fetchMore keeps the events already loaded',
        () async {
      final api = _FakeApi();
      final provider = AudaxEventsCacheProvider(api: api);

      final initial = _fetchFirst(provider);
      api.pending[0].complete(_page([_event('a')], next: 'page2'));
      await initial;

      final more = provider.fetchMore(_key);
      api.pending[1].completeError(TypeError());
      await more;

      expect(_ids(provider), ['a'], reason: 'a failed page must not lose data');
      expect(provider.moreErrorFor(_key), isNotNull);
      expect(provider.isLoadingMore(_key), isFalse);
    });
  });
}
