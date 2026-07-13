import 'package:flutter/foundation.dart';

import '../models/ride.dart';
import '../models/weather_point.dart';
import '../services/offline_ride_store.dart';

/// App-wide state for offline-saved routes: the list shown on the Offline
/// Rides screen, per-ride save progress, and which rides are already saved
/// (so the ride detail can show "Saved ✓").
///
/// Registered once above the navigator (see `main.dart`) so save state set on
/// a ride detail is reflected on the offline list and vice versa.
class OfflineRidesProvider extends ChangeNotifier {
  final OfflineRideStore _store = OfflineRideStore();

  List<OfflineRide> _rides = [];
  bool isLoading = false;
  String? error;

  final Set<int> _savedIds = {};
  final Set<int> _savingIds = {};

  List<OfflineRide> get rides => _rides;
  bool isSaved(int id) => _savedIds.contains(id);
  bool isSaving(int id) => _savingIds.contains(id);

  /// Loads the saved-rides list from disk (newest first).
  Future<void> refresh() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      _rides = await _store.list();
      _savedIds
        ..clear()
        ..addAll(_rides.map((r) => r.ride.id));
    } catch (_) {
      error = 'Could not load your offline rides.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Refreshes just whether one ride is saved — cheap enough to call when a
  /// ride detail opens so its Save button shows the right state.
  Future<void> refreshSavedState(int id) async {
    if (await _store.isSaved(id)) {
      _savedIds.add(id);
    } else {
      _savedIds.remove(id);
    }
    notifyListeners();
  }

  /// Saves a ride (route + weather) for offline use. Returns null on success or
  /// a user-facing error message on failure.
  Future<String?> save(Ride ride, List<WeatherPoint> weather) async {
    _savingIds.add(ride.id);
    notifyListeners();
    try {
      await _store.save(ride, weather);
      _savedIds.add(ride.id);
      final loaded = await _store.load(ride.id);
      if (loaded != null) {
        _rides = [
          loaded,
          for (final r in _rides) if (r.ride.id != ride.id) r,
        ];
      }
      return null;
    } on OfflineSaveException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not save this ride offline. Please try again.';
    } finally {
      _savingIds.remove(ride.id);
      notifyListeners();
    }
  }

  Future<void> delete(int id) async {
    await _store.delete(id);
    _rides = [for (final r in _rides) if (r.ride.id != id) r];
    _savedIds.remove(id);
    notifyListeners();
  }
}
