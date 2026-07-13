import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/models/ride.dart';
import '../services/location_service.dart';

class LiveTrackingProvider extends ChangeNotifier {
  final Ride ride;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSub;

  LiveTrackingProvider(this.ride);

  Position? position;
  double? traveledDistanceKm;
  double? offRouteMeters;

  bool isLoading = false;
  String? error;
  String? permissionMessage;

  Future<void> start() async {
    isLoading = true;
    error = null;
    permissionMessage = null;
    notifyListeners();

    try {
      await _locationService.ensureReady();
    } on LocationPermissionDenied catch (e) {
      permissionMessage = e.message;
      isLoading = false;
      notifyListeners();
      return;
    }

    isLoading = false;
    notifyListeners();

    _positionSub?.cancel();
    _positionSub = _locationService.positionStream().listen(_onPosition);
  }

  void _onPosition(Position pos) {
    position = pos;
    final profile = ride.profile;
    if (profile != null && profile.latitude.isNotEmpty) {
      var bestIdx = 0;
      var bestMeters = double.infinity;
      for (var i = 0; i < profile.latitude.length; i++) {
        final d = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          profile.latitude[i],
          profile.longitude[i],
        );
        if (d < bestMeters) {
          bestMeters = d;
          bestIdx = i;
        }
      }
      offRouteMeters = bestMeters;
      traveledDistanceKm = profile.distanceKm[bestIdx];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
