import 'package:flutter/foundation.dart';

import '../../../core/models/ride.dart';
import '../../../core/models/ride_section.dart';
import '../../../core/models/weather_point.dart';
import '../services/offline_ride_store.dart';

/// App-wide state for offline-saved routes: the list shown on the Offline
/// Rides screen, per-ride save progress, and which rides are already saved
/// (so the ride detail can show "Saved ✓").
///
/// Registered once above the navigator (see `main.dart`) so save state set on
/// a ride detail is reflected on the offline list and vice versa.
class OfflineRidesProvider extends ChangeNotifier {
  /// Defaults to the real on-disk store, so callers say
  /// `OfflineRidesProvider()`. Tests pass a fake — both to stage the
  /// save-during-refresh ordering the [_generation] guard exists for, and
  /// because the real store needs a `path_provider` documents directory that
  /// doesn't exist under `flutter test`.
  OfflineRidesProvider({OfflineRideStore? store})
      : _store = store ?? OfflineRideStore();

  final OfflineRideStore _store;

  List<OfflineRide> _rides = [];
  bool isLoading = false;
  String? error;

  final Set<int> _savedIds = {};
  final Set<int> _savingIds = {};

  /// Bumped by every [refresh], and by [save]/[delete] once they've written to
  /// disk — a completed write knows the disk better than any read that started
  /// before it, so it invalidates those reads.
  ///
  /// Without this, a [refresh] whose `list()` snapshot was taken *before* a
  /// save finished would land afterwards and rebuild [_savedIds] from that
  /// stale snapshot, flipping the just-saved ride's "Saved ✓" back to unsaved
  /// even though its data is sitting on disk.
  int _generation = 0;

  List<OfflineRide> get rides => _rides;
  bool isSaved(int id) => _savedIds.contains(id);
  bool isSaving(int id) => _savingIds.contains(id);

  /// Loads the saved-rides list from disk (newest first).
  Future<void> refresh() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await _store.list();
      if (generation != _generation) return;
      _rides = loaded;
      _savedIds
        ..clear()
        ..addAll(_rides.map((r) => r.ride.id));
    } catch (_) {
      if (generation != _generation) return;
      error = 'Could not load your offline rides.';
    } finally {
      // Always clears, even when superseded — unlike RidesProvider, where only
      // a fetch invalidates a fetch and the newer one is guaranteed to own the
      // flag. Here a [save] can invalidate a read without ever setting
      // isLoading, so skipping this would strand the spinner on forever.
      // The cost is that two overlapping refreshes can drop the spinner a beat
      // early, showing correct-but-previous data until the newer read lands.
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

  /// Saves a ride (route + weather + notable sections) for offline use. Returns
  /// null on success or a user-facing error message on failure.
  Future<String?> save(
    Ride ride,
    List<WeatherPoint> weather,
    List<RideSection> sections,
  ) async {
    _savingIds.add(ride.id);
    notifyListeners();
    try {
      await _store.save(ride, weather, sections);
      // Disk has changed: discard any refresh still reading the old state.
      _generation++;
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
    _generation++; // as in [save] — this write outranks any in-flight read
    _rides = [for (final r in _rides) if (r.ride.id != id) r];
    _savedIds.remove(id);
    notifyListeners();
  }
}
