import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/ride.dart';

enum RideSort { newest, nameAsc, distanceAsc, distanceDesc }

class RidesProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  List<Ride> _rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;
  RideSort sort = RideSort.newest;

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

  Future<void> loadFirst() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listRides();
      _rides = page.results;
      _nextUrl = page.next;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || isLoadingMore) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _api.listRides(pageUrl: _nextUrl);
      _rides = [..._rides, ...page.results];
      _nextUrl = page.next;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFirst();

  Future<Ride?> upload({required String filePath, String? name}) async {
    error = null;
    try {
      final ride = await _api.uploadRide(filePath: filePath, name: name);
      _rides = [ride, ..._rides];
      notifyListeners();
      return ride;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return null;
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
