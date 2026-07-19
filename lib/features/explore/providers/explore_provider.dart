import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';
import '../../../core/models/route_suggestion.dart';
import '../../tracking/services/location_service.dart';

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
  ExploreProvider({ApiClient? api, LocationService? location})
      : _api = api ?? ApiClient.instance,
        _location = location ?? LocationService();

  final ApiClient _api;
  final LocationService _location;

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

  /// The city behind the current nearby search, when it was reached via
  /// [searchNearCity] rather than a picked map point — mutually exclusive
  /// with [pickedPlace]. Kept so the "Near ..." header can show what's
  /// actually driving the search.
  String? pickedCity;
  List<RouteSuggestion> nearby = [];
  bool isLoadingNearby = false;
  String? nearbyError;

  // --- Location-fallback city picker --------------------------------------

  /// Set once [loadFirstNearby] can't get a location fix, so the browse list
  /// (all rides, unfiltered by distance) can tell the rider why they're
  /// seeing everything and offer the same city search [searchNearCity] uses.
  bool locationFailed = false;
  List<String> cities = [];
  bool citiesLoading = false;

  /// Bumped by every fetch in either mode, so a slow response from a
  /// superseded request (a `loadMore` after a fresh `loadFirst`, or a second
  /// place picked before the first search returns) can recognise itself as
  /// stale and get dropped instead of corrupting newer results — same
  /// reasoning as [RidesProvider._generation].
  int _generation = 0;

  /// Attempts to load rides near the user's location (25km radius). If
  /// location access fails, falls back to [loadFirst] (all approved rides)
  /// and pre-fetches [cities] so the rider can search by city instead of
  /// seeing an unfiltered list with no way out.
  Future<void> loadFirstNearby() async {
    try {
      await _location.ensureReady();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await searchNear(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      locationFailed = true;
      notifyListeners();
      await loadFirst();
      await loadCities();
    }
  }

  /// Fetches the curated-route city list once and caches it; safe to call
  /// repeatedly (e.g. both eagerly from [loadFirstNearby] and again if the
  /// rider taps "search by city" before that finishes).
  Future<void> loadCities() async {
    if (cities.isNotEmpty || citiesLoading) return;
    citiesLoading = true;
    notifyListeners();
    try {
      cities = await _api.getSuggestionLocations();
    } catch (_) {
      // The city list is a convenience; leave it empty on failure and let
      // the rider retry "near me" instead.
    } finally {
      citiesLoading = false;
      notifyListeners();
    }
  }

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
    pickedCity = null;
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

  /// Switches to [ExploreMode.nearby] and searches curated rides in [city] —
  /// the fallback path when a location fix isn't available, same city-match
  /// mode [RouteSuggestionsPanel] uses via [ApiClient.getRouteSuggestions].
  Future<void> searchNearCity(String city) async {
    final generation = ++_generation;
    mode = ExploreMode.nearby;
    pickedPlace = null;
    pickedCity = city;
    isLoadingNearby = true;
    nearbyError = null;
    notifyListeners();
    try {
      final result = await _api.getRouteSuggestions(city: city);
      if (generation != _generation) return;
      nearby = result.suggestions;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      nearbyError = e.message;
    } catch (_) {
      if (generation != _generation) return;
      nearbyError = "Couldn't load rides in that city.";
    } finally {
      if (generation == _generation) {
        isLoadingNearby = false;
        notifyListeners();
      }
    }
  }

  /// Drops back to [ExploreMode.browse]. Bumps the generation so a nearby
  /// search still in flight can't land afterwards and flip the mode back.
  /// Leaves [locationFailed]/[cities] alone — the location fix genuinely
  /// failed, so the browse list should keep offering the city search.
  ///
  /// [rides] is fetched lazily here rather than eagerly alongside a
  /// successful [searchNear]/[searchNearCity]: when location succeeds
  /// [loadFirstNearby] never touches [loadFirst], so without this the browse
  /// list would still be empty (and show "No approved rides yet") the first
  /// time the rider clears back to it.
  void clearPlace() {
    _generation++;
    mode = ExploreMode.browse;
    pickedPlace = null;
    pickedCity = null;
    nearby = [];
    nearbyError = null;
    isLoadingNearby = false;
    notifyListeners();
    if (rides.isEmpty && !isLoading) loadFirst();
  }
}
