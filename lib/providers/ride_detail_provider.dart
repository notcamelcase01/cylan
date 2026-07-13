import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/ride.dart';

class RideDetailProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  Ride? ride;
  bool isLoading = false;
  bool isApplyingSmoothing = false;
  String? error;

  Future<void> load(int id) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      ride = await _api.getRide(id);
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> applySmoothing(int windowM) async {
    final current = ride;
    if (current == null) return;
    isApplyingSmoothing = true;
    error = null;
    notifyListeners();
    try {
      ride = await _api.setSmoothing(current.id, windowM);
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isApplyingSmoothing = false;
      notifyListeners();
    }
  }
}
