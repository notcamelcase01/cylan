import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';
import '../../tracking/services/location_service.dart';

/// Backs the Explore tab: staff-approved curated rides, paginated, optionally
/// filtered to near a picked place or a picked city ([pickedPlace] /
/// [pickedCity] — mutually exclusive, both null means unfiltered). One list
/// throughout; the filter just changes what `/rides/approved/` is asked for.
/// Screen-scoped like [LikedRidesProvider] (created once by the tab, kept
/// alive by `HomeShell`'s `IndexedStack`).
class ExploreProvider extends ChangeNotifier {
  ExploreProvider({ApiClient? api, LocationService? location})
      : _api = api ?? ApiClient.instance,
        _location = location ?? LocationService();

  final ApiClient _api;
  final LocationService _location;

  List<Ride> rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;

  bool get hasMore => _nextUrl != null;

  LatLng? pickedPlace;
  String? pickedCity;
  bool get isFiltered => pickedPlace != null || pickedCity != null;

  // --- Location-fallback city picker --------------------------------------

  /// Set once [loadFirstNearby] can't get a location fix, so the unfiltered
  /// list can tell the rider why they're seeing everything and offer a city
  /// search instead.
  bool locationFailed = false;
  List<String> cities = [];
  bool citiesLoading = false;

  /// Bumped by every fetch, so a slow response from a superseded request (a
  /// `loadMore` after a fresh `loadFirst`, or a second place picked before
  /// the first search returns) can recognise itself as stale and get dropped
  /// instead of corrupting newer results — same reasoning as
  /// [RidesProvider._generation].
  int _generation = 0;

  /// Attempts to load rides near the user's location (25km radius). If
  /// location access fails, falls back to the unfiltered list and pre-fetches
  /// [cities] so the rider can search by city instead.
  Future<void> loadFirstNearby() async {
    try {
      await _location.ensureReady();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      pickedPlace = LatLng(pos.latitude, pos.longitude);
      pickedCity = null;
      await loadFirst();
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
      final page = await _api.listApprovedRides(
        lat: pickedPlace?.latitude,
        lng: pickedPlace?.longitude,
        city: pickedCity,
      );
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

  /// Refreshes the list, but only when unfiltered — called when `HomeShell`
  /// re-selects this tab (see [LikedRidesProvider] for why: `IndexedStack`
  /// never rebuilds an inactive tab, so nothing else would pick up a
  /// newly-approved ride). A no-op while filtered so merely switching tabs
  /// away and back doesn't clear a rider's place/city search.
  Future<void> refreshIfBrowsing() {
    if (isFiltered) return Future.value();
    return loadFirst();
  }

  /// Filters the list to curated rides near [place]. Picking a new place
  /// while one search is already in flight discards the older answer via the
  /// generation guard, same as pagination.
  Future<void> searchNear(LatLng place) async {
    pickedPlace = place;
    pickedCity = null;
    await loadFirst();
  }

  /// Filters the list to curated rides in [city] — the fallback path when a
  /// location fix isn't available.
  Future<void> searchNearCity(String city) async {
    pickedPlace = null;
    pickedCity = city;
    await loadFirst();
  }

  /// Drops any place/city filter and reloads the full list.
  void clearPlace() {
    pickedPlace = null;
    pickedCity = null;
    loadFirst();
  }
}
