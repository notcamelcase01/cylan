import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/weather_point.dart';

/// App-level cache of fetched weather-along-route results, keyed by ride id.
///
/// Registered once above the navigator (see `main.dart`) so a forecast
/// fetched on the weather screen survives navigating back to the ride
/// detail or rides list — both read from this same cache instead of each
/// screen holding its own throwaway state.
class WeatherCacheProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  final Map<int, List<WeatherPoint>> _points = {};
  final Map<int, bool> _loading = {};
  final Map<int, String?> _errors = {};

  List<WeatherPoint>? pointsFor(int rideId) => _points[rideId];
  bool isLoading(int rideId) => _loading[rideId] ?? false;
  String? errorFor(int rideId) => _errors[rideId];
  bool hasFetched(int rideId) => _points.containsKey(rideId);

  /// First forecast point for a ride, for a compact list/map badge.
  WeatherPoint? summaryFor(int rideId) {
    final pts = _points[rideId];
    if (pts == null || pts.isEmpty) return null;
    return pts.first;
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
      _points[rideId] = await _api.getWeather(rideId, start: start, finish: finish);
    } on ApiException catch (e) {
      _errors[rideId] = e.message;
    } finally {
      _loading[rideId] = false;
      notifyListeners();
    }
  }

  /// Drops the cached forecast for a ride so the weather screen goes back
  /// to its empty state and a fresh fetch can be made.
  void reset(int rideId) {
    _points.remove(rideId);
    _errors.remove(rideId);
    _loading.remove(rideId);
    notifyListeners();
  }
}
