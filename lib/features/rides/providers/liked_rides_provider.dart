import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';

/// Rides the signed-in rider has liked (any owner), paginated — the Liked
/// Rides tab's backing state. Trimmed down from [RidesProvider]: no
/// search/sort/upload, just list + page. Screen-scoped like
/// [RideDetailProvider]/[EventDetailProvider] (created once by the tab and
/// kept alive by `HomeShell`'s `IndexedStack`), not app-level — nothing
/// outside this tab needs to trigger its refresh.
class LikedRidesProvider extends ChangeNotifier {
  LikedRidesProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  List<Ride> rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;

  /// Bumped by every [loadFirst] — see [RidesProvider._generation] for why:
  /// a `loadMore` that resolves after a concurrent refresh must recognise
  /// itself as stale rather than appending onto the new page 1.
  int _generation = 0;

  bool get hasMore => _nextUrl != null;

  Future<void> loadFirst() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listLikedRides();
      if (generation != _generation) return;
      rides = page.results;
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      if (generation != _generation) return;
      error = "Couldn't load your liked rides.";
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
      final page = await _api.listLikedRides(pageUrl: next);
      if (generation != _generation) return;
      rides = [...rides, ...page.results];
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      if (generation != _generation) return;
      error = "Couldn't load more liked rides.";
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();
}
