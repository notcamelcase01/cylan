import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';

enum RideSort { newest, nameAsc, distanceAsc, distanceDesc }

class RidesProvider extends ChangeNotifier {
  /// Defaults to the real client, so callers say `RidesProvider()`. Tests pass
  /// a fake to drive the request orderings the [_generation] guard exists for,
  /// which are otherwise impossible to stage against a live API.
  RidesProvider({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  List<Ride> _rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;
  RideSort sort = RideSort.newest;

  /// Bumped by every [loadFirst], and captured by each in-flight request so a
  /// response can tell whether the list it was built against still exists.
  ///
  /// Cancelling the abandoned request instead would not be enough: cancelling
  /// is itself a race — the response can already be decoded and queued by the
  /// time the cancel lands — so an arriving answer must still be recognised as
  /// stale and dropped. Without this, a scroll-triggered [loadMore] that
  /// resolves *after* a pull-to-refresh splices page 2 of the old list onto
  /// the freshly refreshed page 1, duplicating or dropping rides depending on
  /// what changed server-side.
  int _generation = 0;

  bool get hasMore => _nextUrl != null;

  List<Ride> get rides {
    if (sort == RideSort.newest) return _rides;
    final sorted = [..._rides];
    switch (sort) {
      case RideSort.nameAsc:
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case RideSort.distanceAsc:
        sorted.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      case RideSort.distanceDesc:
        sorted.sort((a, b) => b.distanceKm.compareTo(a.distanceKm));
        break;
      case RideSort.newest:
        break;
    }
    return sorted;
  }

  void setSort(RideSort value) {
    if (sort == value) return;
    sort = value;
    notifyListeners();
  }

  /// Loads (or reloads) page 1, replacing the list. Starting one invalidates
  /// every request already in flight — including a concurrent [loadFirst], so
  /// two overlapping refreshes settle on the newer answer rather than
  /// whichever happens to land last.
  Future<void> loadFirst() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listRides();
      if (generation != _generation) return;
      _rides = page.results;
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      // [ApiClient] only promises an ApiException for transport failures and
      // non-2xx bodies, so a 200 whose body isn't the shape /rides/ returns
      // arrives as a raw TypeError. Without this the list stayed empty with no
      // error set, and the screen rendered "No rides yet" — telling a rider who
      // has plenty that they have none, which reads as data loss.
      if (generation != _generation) return;
      error = "Couldn't load your rides.";
    } finally {
      // A superseded load leaves the flag alone: the newer one set it and
      // still owns it, so clearing it here would hide its spinner.
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
      // The list this page was meant to extend has since been replaced, so
      // it has nowhere to go — appending it now would corrupt the new one.
      if (generation != _generation) return;
      _rides = [..._rides, ...page.results];
      _nextUrl = page.next;
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e.message;
    } catch (_) {
      // As in [loadFirst].
      if (generation != _generation) return;
      error = "Couldn't load more rides.";
    } finally {
      // Unconditional, unlike above: only one loadMore runs at a time (the
      // guard above ensures it), so this call always owns the flag and must
      // release it even when its result was discarded.
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();

  /// Fraction of the current upload that has been sent (0-1), or null when
  /// nothing is uploading or the file's total size isn't known.
  double? uploadProgress;

  Future<Ride?> upload({required String filePath, String? name}) async {
    error = null;
    uploadProgress = null;
    try {
      final ride = await _api.uploadRide(
        filePath: filePath,
        name: name,
        onProgress: (sent, total) {
          // total is -1 when the length isn't known up front; leave the bar
          // indeterminate rather than inventing a number.
          uploadProgress = total > 0 ? sent / total : null;
          notifyListeners();
        },
      );
      _rides = [ride, ..._rides];
      return ride;
    } on ApiException catch (e) {
      error = e.message;
      return null;
    } catch (_) {
      // Not everything that can go wrong here is an ApiException: the picked
      // file can be gone by the time it's read (Android evicts the picker's
      // cache copy), which arrives as a FileSystemException. Letting it escape
      // would break this method's contract — "returns null and sets error" —
      // and stranded the caller's uploading flag with it.
      error = 'Could not read that file. Please pick it again.';
      return null;
    } finally {
      // Whichever way it ended, nothing is in flight now — otherwise the bar
      // would sit frozen at 100% until the next upload.
      uploadProgress = null;
      notifyListeners();
    }
  }

  /// Imports a ride from a Google Maps directions link. India only; the
  /// server rejects anything else with a displayable error, surfaced via
  /// [error] like every other failure here.
  Future<Ride?> importFromGoogleMaps({required String url, String? name}) async {
    error = null;
    try {
      final ride = await _api.importFromGoogleMaps(url: url, name: name);
      _rides = [ride, ..._rides];
      return ride;
    } on ApiException catch (e) {
      error = e.message;
      return null;
    } catch (_) {
      // As in loadFirst: not every failure here is an ApiException (a 2xx
      // whose body isn't the expected shape arrives as a raw TypeError), and
      // letting that escape would break this method's contract and leave the
      // caller's busy flag stuck on.
      error = "Couldn't import that route. Please try again.";
      return null;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> rename(int id, String name) async {
    try {
      final updated = await _api.renameRide(id, name);
      _rides = [
        for (final r in _rides) if (r.id == id) updated else r,
      ];
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> delete(int id) async {
    try {
      await _api.deleteRide(id);
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
