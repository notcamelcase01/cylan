import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';
import '../../../core/models/route_suggestion.dart';

enum ExploreMode {
  /// All staff-approved curated rides, paginated, newest first.
  browse,

  /// Curated rides near a place the rider picked on the map (25 km radius,
  /// same as the event-creation suggestions panel — see
  /// [ApiClient.getRouteSuggestions]).
  nearby,
}

/// Backs the Explore tab: either the flat approved-rides list, or curated
/// suggestions near a picked point, never both at once — [mode] says which.
/// Screen-scoped like [LikedRidesProvider] (created once by the tab, kept
/// alive by `HomeShell`'s `IndexedStack`).
class ExploreProvider extends ChangeNotifier {
  ExploreProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  ExploreMode mode = ExploreMode.browse;

  // --- Browse mode: paginated approved rides ------------------------------

  List<Ride> rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;

  bool get hasMore => _nextUrl != null;

  // --- Nearby mode: one-shot suggestions near a picked place --------------

  LatLng? pickedPlace;
  List<RouteSuggestion> nearby = [];
  bool isLoadingNearby = false;
  String? nearbyError;

  /// Bumped by every fetch in either mode, so a slow response from a
  /// superseded request (a `loadMore` after a fresh `loadFirst`, or a second
  /// place picked before the first search returns) can recognise itself as
  /// stale and get dropped instead of corrupting newer results — same
  /// reasoning as [RidesProvider._generation].
  int _generation = 0;

  Future<void> loadFirst() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listApprovedRides();
      if (generation != _generation) return;
      rides = page.results;
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      if (generation != _generation) return;
      error = "Couldn't load approved rides.";
    } finally {
      if (generation == _generation) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || isLoadingMore) return;
    final generation = _generation;
    final next = _nextUrl;
    isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _api.listApprovedRides(pageUrl: next);
      if (generation != _generation) return;
      rides = [...rides, ...page.results];
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      if (generation != _generation) return;
      error = "Couldn't load more approved rides.";
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();

  /// Refreshes the browse list, but only when actually browsing — called
  /// when `HomeShell` re-selects this tab (see [LikedRidesProvider] for why:
  /// `IndexedStack` never rebuilds an inactive tab, so nothing else would
  /// pick up a newly-approved ride). A no-op in [ExploreMode.nearby] so
  /// merely switching tabs away and back doesn't clear a rider's place
  /// search.
  Future<void> refreshIfBrowsing() {
    if (mode != ExploreMode.browse) return Future.value();
    return loadFirst();
  }

  /// Switches to [ExploreMode.nearby] and searches around [place]. Picking a
  /// new place while one search is already in flight discards the older
  /// answer via the generation guard, same as the browse-mode pagination.
  Future<void> searchNear(LatLng place) async {
    final generation = ++_generation;
    mode = ExploreMode.nearby;
    pickedPlace = place;
    isLoadingNearby = true;
    nearbyError = null;
    notifyListeners();
    try {
      final result = await _api.getRouteSuggestions(
        lat: place.latitude,
        lng: place.longitude,
      );
      if (generation != _generation) return;
      nearby = result.suggestions;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      nearbyError = e.message;
    } catch (_) {
      if (generation != _generation) return;
      nearbyError = "Couldn't load rides near that place.";
    } finally {
      if (generation == _generation) {
        isLoadingNearby = false;
        notifyListeners();
      }
    }
  }

  /// Drops back to [ExploreMode.browse]. Bumps the generation so a nearby
  /// search still in flight can't land afterwards and flip the mode back.
  void clearPlace() {
    _generation++;
    mode = ExploreMode.browse;
    pickedPlace = null;
    nearby = [];
    nearbyError = null;
    isLoadingNearby = false;
    notifyListeners();
  }
}
