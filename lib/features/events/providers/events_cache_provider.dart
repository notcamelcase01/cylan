import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/event.dart';

/// App-level, session-only cache for the app-native events list, keyed by
/// filter combination (mine/status/visibility/q/location/upcoming). Same shape
/// as [AudaxEventsCacheProvider]: registered once above the navigator (see
/// `main.dart`) so a filter combo fetched once during this run isn't re-fetched
/// when the events tab is left and reopened. In-memory only.
///
/// Unlike the Audax cache this holds *mutable* user data — creating, editing,
/// subscribing to, or deleting an event changes what a list should show — so it
/// exposes [invalidate] for the create/edit/detail flows to call, dropping the
/// stale pages so the next open refetches.
class EventsCacheProvider extends ChangeNotifier {
  EventsCacheProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  final Map<String, List<Event>> _events = {};
  final Map<String, String?> _nextUrls = {};
  final Map<String, bool> _loadingFirst = {};
  final Map<String, bool> _loadingMore = {};
  final Map<String, String?> _firstErrors = {};
  final Map<String, String?> _moreErrors = {};

  /// Bumped by every [fetchFirst] that goes out, captured per in-flight request
  /// so a late response can tell whether the list it was built against still
  /// exists. Ported from [AudaxEventsCacheProvider] / `RidesProvider` for the
  /// identical reason: without it a scroll-triggered [fetchMore] resolving after
  /// a refresh splices the old page 2 onto the fresh page 1.
  final Map<String, int> _generations = {};

  int _generationOf(String key) => _generations[key] ?? 0;

  /// Builds the cache key for a filter combination. Same inputs → same entry.
  static String keyFor({
    bool mine = false,
    String? status,
    String? visibility,
    String? q,
    String? location,
    bool upcomingOnly = false,
  }) =>
      [
        mine,
        status ?? '',
        visibility ?? '',
        q ?? '',
        location ?? '',
        upcomingOnly,
      ].join('|');

  List<Event>? eventsFor(String key) => _events[key];
  bool hasMore(String key) => _nextUrls[key] != null;
  bool hasFetched(String key) => _events.containsKey(key);
  bool isLoadingFirst(String key) => _loadingFirst[key] == true;
  bool isLoadingMore(String key) => _loadingMore[key] == true;
  String? firstErrorFor(String key) => _firstErrors[key];
  String? moreErrorFor(String key) => _moreErrors[key];

  /// Fetches page 1 for [key] unless already cached (or in flight). Pass
  /// [force] to bypass the cache (pull-to-refresh); a failed forced refresh
  /// keeps whatever was cached, surfacing the error alongside stale data.
  Future<void> fetchFirst(
    String key, {
    bool mine = false,
    String? status,
    String? visibility,
    String? q,
    String? location,
    bool upcomingOnly = false,
    bool force = false,
  }) async {
    if (!force && (hasFetched(key) || isLoadingFirst(key))) return;
    final generation = _generations[key] = _generationOf(key) + 1;
    _loadingFirst[key] = true;
    _firstErrors[key] = null;
    notifyListeners();
    try {
      final page = await _api.listEvents(
        mine: mine,
        status: status,
        visibility: visibility,
        q: q,
        location: location,
        upcoming: upcomingOnly ? true : null,
      );
      if (generation != _generationOf(key)) return;
      _events[key] = page.results;
      _nextUrls[key] = page.next;
      _moreErrors[key] = null;
    } on ApiException catch (e) {
      if (generation != _generationOf(key)) return;
      _firstErrors[key] = e.message;
    } catch (_) {
      // [ApiClient] only guarantees an ApiException for transport failures and
      // non-2xx bodies; a 200 whose shape is unexpected still surfaces as a raw
      // TypeError. Catching it keeps the key from being left with no events, no
      // error, and no spinner — which the screen renders as a dead spinner.
      if (generation != _generationOf(key)) return;
      _firstErrors[key] = "Couldn't load these events.";
    } finally {
      if (generation == _generationOf(key)) {
        _loadingFirst[key] = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page for [key]. No-op with no more data or an in-flight
  /// fetch. A failure keeps the loaded events and just records the error.
  Future<void> fetchMore(String key) async {
    final next = _nextUrls[key];
    if (next == null || isLoadingMore(key)) return;
    final generation = _generationOf(key);
    _loadingMore[key] = true;
    _moreErrors[key] = null;
    notifyListeners();
    try {
      final page = await _api.listEvents(pageUrl: next);
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
      _loadingMore[key] = false;
      notifyListeners();
    }
  }

  /// Drops every cached page so the next [fetchFirst] refetches. Called after a
  /// create/edit/delete/subscribe, since any of those can change what a list
  /// (especially the "mine" list, or a search) should contain, and there's no
  /// cheap way to know which keys are affected. Bumps generations for every
  /// key with *any* tracked state — not just successfully cached ones — so a
  /// [fetchFirst] that's still in flight (not yet in [_events]) is also
  /// recognised as stale by its own completion. Without covering that case, an
  /// in-flight request's `finally` would wrongly match the (unbumped)
  /// generation and appear to finish normally, while the loading flag this
  /// call is about to clear no longer reflects it — leaving a later
  /// [fetchFirst] free to race a second request for the same key.
  void invalidate() {
    final keys = {
      ..._events.keys,
      ..._loadingFirst.keys,
      ..._loadingMore.keys,
      ..._nextUrls.keys,
    };
    for (final key in keys) {
      _generations[key] = _generationOf(key) + 1;
    }
    _events.clear();
    _nextUrls.clear();
    _loadingFirst.clear();
    _loadingMore.clear();
    _firstErrors.clear();
    _moreErrors.clear();
    notifyListeners();
  }
}
