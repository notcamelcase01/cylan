import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/models/ride.dart';
import '../services/location_service.dart';

class LiveTrackingProvider extends ChangeNotifier {
  final Ride ride;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSub;

  /// Whether the screen that owns this has already gone away. [start] waits on
  /// the OS permission prompt, which the rider can leave sitting open for as
  /// long as they like — and back out of — so by the time it returns, this
  /// provider may be long disposed.
  bool _disposed = false;

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
      if (_disposed) return;
      permissionMessage = e.message;
      isLoading = false;
      notifyListeners();
      return;
    } catch (_) {
      // Anything else the platform throws (a geolocator PlatformException, say)
      // would otherwise escape and leave isLoading pinned true — a spinner the
      // rider can never get past, on the one screen they're using mid-ride.
      if (_disposed) return;
      error = "Couldn't start location tracking. Please try again.";
      isLoading = false;
      notifyListeners();
      return;
    }

    // Subscribing now would open a GPS stream that dispose() has already run
    // past and will never cancel — it would keep the receiver awake, and keep
    // draining the battery, for the rest of the process's life.
    if (_disposed) return;

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
    _disposed = true;
    _positionSub?.cancel();
    super.dispose();
  }
}
