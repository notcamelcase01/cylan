import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';

class RideDetailProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  Ride? ride;
  bool isLoading = false;
  bool isApplyingSmoothing = false;
  String? error;
  bool isLiked = false;

  Future<void> load(int id) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      ride = await _api.getRide(id);
      isLiked = ride!.isLiked;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleLike() async {
    final current = ride;
    if (current == null) return;
    final wasLiked = isLiked;
    final nowLiked = !wasLiked;
    isLiked = nowLiked;
    notifyListeners();
    try {
      final newCount =
          wasLiked ? await _api.unlikeRide(current.id) : await _api.likeRide(current.id);
      ride = Ride(
        id: current.id,
        name: current.name,
        sourceFormat: current.sourceFormat,
        recordedAt: current.recordedAt,
        createdAt: current.createdAt,
        distanceKm: current.distanceKm,
        distanceM: current.distanceM,
        totalAscentM: current.totalAscentM,
        totalDescentM: current.totalDescentM,
        minElevationM: current.minElevationM,
        maxElevationM: current.maxElevationM,
        netElevationM: current.netElevationM,
        maxGradientPct: current.maxGradientPct,
        minGradientPct: current.minGradientPct,
        pointCount: current.pointCount,
        likesCount: newCount,
        isLiked: nowLiked,
        visibility: current.visibility,
        originalFilename: current.originalFilename,
        profile: current.profile,
        smoothingWindowM: current.smoothingWindowM,
      );
    } on ApiException catch (e) {
      isLiked = wasLiked;
      error = e.message;
    }
    notifyListeners();
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
