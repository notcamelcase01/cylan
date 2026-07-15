import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/audax_event.dart';

/// App-level, session-only cache for the Audax events calendar, keyed by
/// query (month/year + filters) — same shape as `WeatherCacheProvider` /
/// `SectionsCacheProvider`. Registered once above the navigator (see
/// `main.dart`) so a month/filter combo fetched once during this app run is
/// never re-fetched, even after leaving and reopening the screen. It's
/// in-memory only (no disk write), so it naturally disappears when the app
/// process ends — nothing to explicitly clear.
class AudaxEventsCacheProvider extends ChangeNotifier {
  /// Defaults to the real client, so callers say `AudaxEventsCacheProvider()`.
  /// Tests pass a fake to drive the request orderings the [_generations] guard
  /// exists for, which are otherwise impossible to stage against a live API.
  AudaxEventsCacheProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  // --- Filter options (categories/states/cities) — one global resource ----

  AudaxEventFilters? _filters;
  bool _filtersLoading = false;
  String? _filtersError;

  AudaxEventFilters? get filters => _filters;
  bool get filtersLoading => _filtersLoading;
  String? get filtersError => _filtersError;

  /// Fetches the filter options once per session; a no-op if already fetched
  /// or a fetch is in flight, so it's safe to call every time the screen
  /// opens. Pass [force] to retry after a failure.
  Future<void> fetchFilters({bool force = false}) async {
    if (!force && (_filters != null || _filtersLoading)) return;
    _filtersLoading = true;
    _filtersError = null;
    notifyListeners();
    try {
      _filters = await _api.getAudaxEventFilters();
    } on ApiException catch (e) {
      _filtersError = e.message;
    } catch (_) {
      // See [fetchFirst] for why `on ApiException` alone isn't enough.
      _filtersError = "Couldn't load the filter options.";
    } finally {
      _filtersLoading = false;
      notifyListeners();
    }
  }

  // --- Event pages, keyed by month/year + filters --------------------------
  //
  // "First" (page 1, via fetchFirst) and "more" (page 2+, via fetchMore) each
  // get their own loading/error state per key, so a failed pull-to-refresh
  // (a forced fetchFirst) never gets mistaken for a failed "load more" — they
  // drive different bits of UI (a full-screen retry vs. a trailing list row).

  final Map<String, List<AudaxEvent>> _events = {};
  final Map<String, String?> _nextUrls = {};
  final Map<String, bool> _loadingFirst = {};
  final Map<String, bool> _loadingMore = {};
  final Map<String, String?> _firstErrors = {};
  final Map<String, String?> _moreErrors = {};

  /// Bumped by every [fetchFirst] that actually goes out, and captured by each
  /// in-flight request so a response can tell whether the list it was built
  /// against still exists. Per key, since each month/filter combo is its own
  /// independent list and a refresh of one says nothing about the others.
  ///
  /// This is `RidesProvider._generation` ported across, and it's here for the
  /// identical reason: without it, a scroll-triggered [fetchMore] that resolves
  /// *after* a pull-to-refresh splices page 2 of the old list onto the freshly
  /// refreshed page 1 — duplicating or dropping events depending on what
  /// changed server-side — and leaves [_nextUrls] pointing into a list that no
  /// longer exists, so every later page continues the wrong one.
  ///
  /// Cancelling the abandoned request instead would not be enough: cancelling
  /// is itself a race, so an arriving answer must still be recognised as stale
  /// and dropped.
  final Map<String, int> _generations = {};

  int _generationOf(String key) => _generations[key] ?? 0;

  /// Builds the cache key for a given month + filter combination. Two calls
  /// with the same inputs always resolve to the same cached entry.
  static String keyFor({
    required int year,
    required int month,
    required bool upcomingOnly,
    String? city,
    String? state,
    String? category,
  }) =>
      [year, month, upcomingOnly, city ?? '', state ?? '', category ?? '']
          .join('|');

  List<AudaxEvent>? eventsFor(String key) => _events[key];
  bool hasMore(String key) => _nextUrls[key] != null;
  bool hasFetched(String key) => _events.containsKey(key);
  bool isLoadingFirst(String key) => _loadingFirst[key] == true;
  bool isLoadingMore(String key) => _loadingMore[key] == true;
  String? firstErrorFor(String key) => _firstErrors[key];
  String? moreErrorFor(String key) => _moreErrors[key];

  /// Fetches page 1 for [key] unless already cached (or already in flight),
  /// so revisiting the same month/filter combo within this app session is
  /// instant. Pass [force] to bypass the cache (e.g. pull-to-refresh) — a
  /// failed forced refresh keeps whatever was cached before, so the screen
  /// doesn't go blank, just surfaces the error alongside the stale data.
  Future<void> fetchFirst(
    String key, {
    required int month,
    required int year,
    required bool upcomingOnly,
    String? city,
    String? state,
    String? category,
    bool force = false,
  }) async {
    if (!force && (hasFetched(key) || isLoadingFirst(key))) return;
    final generation = _generations[key] = _generationOf(key) + 1;
    _loadingFirst[key] = true;
    _firstErrors[key] = null;
    notifyListeners();
    try {
      final page = await _api.listAudaxEvents(
        month: month,
        year: year,
        upcoming: upcomingOnly ? true : null,
        city: city,
        state: state,
        category: category,
      );
      if (generation != _generationOf(key)) return;
      _events[key] = page.results;
      _nextUrls[key] = page.next;
      _moreErrors[key] = null;
    } on ApiException catch (e) {
      if (generation != _generationOf(key)) return;
      _firstErrors[key] = e.message;
    } catch (_) {
      // `on ApiException` alone isn't enough: [ApiClient] only promises an
      // ApiException for transport failures and non-2xx bodies, so a 200 whose
      // body isn't the shape this endpoint expects still surfaces as a raw
      // TypeError. Letting that escape left this key with no events, no error
      // *and* no spinner — which the screen renders as its "fetch hasn't
      // started yet" branch: a spinner with no retry and no way out of it.
      // Whatever went wrong, the rider needs to be able to ask again.
      if (generation != _generationOf(key)) return;
      _firstErrors[key] = "Couldn't load these events.";
    } finally {
      // A superseded fetch leaves the flag alone: the newer one set it and
      // still owns it, so clearing it here would hide its spinner.
      if (generation == _generationOf(key)) {
        _loadingFirst[key] = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page for [key]. No-op if there's no more data or a
  /// fetch is already in flight. A failure leaves the already-loaded events
  /// in place and just records the error, so the list doesn't lose data.
  Future<void> fetchMore(String key) async {
    final next = _nextUrls[key];
    if (next == null || isLoadingMore(key)) return;
    final generation = _generationOf(key);
    _loadingMore[key] = true;
    _moreErrors[key] = null;
    notifyListeners();
    try {
      final page = await _api.listAudaxEvents(pageUrl: next);
      // The list this page was meant to extend has since been replaced, so it
      // has nowhere to go — appending it now would corrupt the new one, and
      // moving the cursor would point every later page at the old list.
      if (generation != _generationOf(key)) return;
      _events[key] = [...?_events[key], ...page.results];
      _nextUrls[key] = page.next;
    } on ApiException catch (e) {
      if (generation != _generationOf(key)) return;
      _moreErrors[key] = e.message;
    } catch (_) {
      if (generation != _generationOf(key)) return;
      _moreErrors[key] = "Couldn't load more events.";
    } finally {
      // Unconditional, unlike [fetchFirst]: only one fetchMore per key runs at
      // a time (the guard above ensures it), so this call always owns the flag
      // and must release it even when its result was discarded.
      _loadingMore[key] = false;
      notifyListeners();
    }
  }
}
