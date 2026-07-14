import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/weather_point.dart';
import '../services/weather_store.dart';

/// App-level cache of fetched weather-along-route results, keyed by ride id.
///
/// Registered once above the navigator (see `main.dart`) so a forecast
/// fetched on the weather screen survives navigating back to the ride
/// detail or rides list — both read from this same cache instead of each
/// screen holding its own throwaway state.
///
/// It's also written to disk ([WeatherStore]) so a forecast — and the icon it
/// puts on the rides list — survives closing the app. Persistence is
/// best-effort and never fails a fetch: the worst case is the forecast simply
/// doesn't come back next launch. Entries are dropped once their planned
/// window has passed, so a stale badge can't outlive the ride it was for.
class WeatherCacheProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;
  final WeatherStore _store = WeatherStore();

  final Map<int, List<WeatherPoint>> _points = {};
  final Map<int, DateTime> _fetchedAt = {};
  final Map<int, bool> _loading = {};
  final Map<int, String?> _errors = {};

  List<WeatherPoint>? pointsFor(int rideId) => _points[rideId];
  bool isLoading(int rideId) => _loading[rideId] ?? false;
  String? errorFor(int rideId) => _errors[rideId];
  bool hasFetched(int rideId) => _points.containsKey(rideId);

  /// When the cached forecast for a ride was fetched — which can be a previous
  /// app session now that forecasts persist, so the weather screen shows it
  /// rather than letting old data pass for fresh.
  DateTime? fetchedAtFor(int rideId) => _fetchedAt[rideId];

  /// First forecast point for a ride, for a compact list/map badge.
  WeatherPoint? summaryFor(int rideId) {
    final pts = _points[rideId];
    if (pts == null || pts.isEmpty) return null;
    return pts.first;
  }

  /// Loads previously fetched forecasts from disk. Called once at startup
  /// (see `main.dart`); a cache that won't load isn't worth surfacing, since
  /// the user can always refetch.
  Future<void> restore() async {
    try {
      final saved = await _store.loadAll();
      if (saved.isEmpty) return;
      for (final entry in saved.entries) {
        _points[entry.key] = entry.value.points;
        _fetchedAt[entry.key] = entry.value.fetchedAt;
      }
      notifyListeners();
    } catch (_) {
      // Ignored on purpose — an unreadable cache just means no cache.
    }
  }

  Future<void> fetch(
    int rideId, {
    required DateTime start,
    required DateTime finish,
  }) async {
    _loading[rideId] = true;
    _errors[rideId] = null;
    notifyListeners();
    try {
      final points = await _api.getWeather(rideId, start: start, finish: finish);
      final fetchedAt = DateTime.now();
      _points[rideId] = points;
      _fetchedAt[rideId] = fetchedAt;
      try {
        await _store.save(
          rideId,
          CachedForecast(
            points: points,
            start: start,
            finish: finish,
            fetchedAt: fetchedAt,
          ),
        );
      } catch (_) {
        // Best-effort: the fetch succeeded and is usable in memory, so a
        // failed write shouldn't look like a failed forecast.
      }
    } on ApiException catch (e) {
      _errors[rideId] = e.message;
    } finally {
      _loading[rideId] = false;
      notifyListeners();
    }
  }

  /// Drops the cached forecast for a ride, on disk as well as in memory, so
  /// the weather screen goes back to its empty state and a fresh fetch can be
  /// made.
  Future<void> reset(int rideId) async {
    _points.remove(rideId);
    _fetchedAt.remove(rideId);
    _errors.remove(rideId);
    _loading.remove(rideId);
    notifyListeners();
    try {
      await _store.delete(rideId);
    } catch (_) {
      // The in-memory entry is already gone; a leftover file will be
      // overwritten on the next fetch or dropped when its window passes.
    }
  }
}
