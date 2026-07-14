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
  final ApiClient _api = ApiClient.instance;

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
      _events[key] = page.results;
      _nextUrls[key] = page.next;
      _moreErrors[key] = null;
    } on ApiException catch (e) {
      _firstErrors[key] = e.message;
    } finally {
      _loadingFirst[key] = false;
      notifyListeners();
    }
  }

  /// Appends the next page for [key]. No-op if there's no more data or a
  /// fetch is already in flight. A failure leaves the already-loaded events
  /// in place and just records the error, so the list doesn't lose data.
  Future<void> fetchMore(String key) async {
    final next = _nextUrls[key];
    if (next == null || isLoadingMore(key)) return;
    _loadingMore[key] = true;
    _moreErrors[key] = null;
    notifyListeners();
    try {
      final page = await _api.listAudaxEvents(pageUrl: next);
      _events[key] = [...?_events[key], ...page.results];
      _nextUrls[key] = page.next;
    } on ApiException catch (e) {
      _moreErrors[key] = e.message;
    } finally {
      _loadingMore[key] = false;
      notifyListeners();
    }
  }
}
