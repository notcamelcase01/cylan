import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';

/// The Public Rides tab's list: the rider's own rides opted into the
/// curated-suggestion pool (`public_suggestion_status != NONE`), newest
/// first. Same shape as [RidesProvider] — paginated, generation-guarded — but
/// kept as its own provider because it's a distinct, server-side-filtered
/// list rather than a second mode of "My Rides".
class SuggestedRidesProvider extends ChangeNotifier {
  SuggestedRidesProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  List<Ride> _rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;

  /// Bumped by every [loadFirst]; see `RidesProvider._generation` for why —
  /// same race between a scroll-triggered [loadMore] and a pull-to-refresh.
  int _generation = 0;

  List<Ride> get rides => _rides;
  bool get hasMore => _nextUrl != null;

  Future<void> loadFirst() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listRides(suggested: true);
      if (generation != _generation) return;
      _rides = page.results;
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      // As in RidesProvider.loadFirst: a 200 with an unexpectedly-shaped body
      // must not read as "no public suggestions".
      if (generation != _generation) return;
      error = "Couldn't load your public suggestions.";
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
      final page = await _api.listRides(pageUrl: next);
      if (generation != _generation) return;
      _rides = [..._rides, ...page.results];
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      if (generation != _generation) return;
      error = "Couldn't load more suggestions.";
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();

  /// Reverts [id] to `NONE` and drops it from this list on success.
  Future<bool> unsuggest(int id) async {
    try {
      await _api.unsuggestRide(id);
      _rides = _rides.where((r) => r.id != id).toList();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }
}
