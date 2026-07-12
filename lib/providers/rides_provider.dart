import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/ride.dart';

class RidesProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  List<Ride> rides = [];
  String? _nextUrl;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? error;

  bool get hasMore => _nextUrl != null;

  Future<void> loadFirst() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _api.listRides();
      rides = page.results;
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
      rides = [...rides, ...page.results];
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
      rides = [ride, ...rides];
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
      rides = [
        for (final r in rides) if (r.id == id) updated else r,
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
      rides = rides.where((r) => r.id != id).toList();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }
}
