import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/ride.dart';
import '../models/turn.dart';
import '../services/location_service.dart';
import '../services/turn_detection.dart';

class LiveTrackingProvider extends ChangeNotifier {
  final Ride ride;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSub;

  LiveTrackingProvider(this.ride);

  List<Turn> turns = [];
  Position? position;
  double? traveledDistanceKm;
  double? offRouteMeters;
  Turn? nextTurn;
  double? distanceToNextTurnKm;

  /// Upcoming turns (next few), for the cue list.
  List<Turn> upcomingTurns = [];

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

    // Turns are computed entirely on-device from the ride's stored profile —
    // no server round-trip while riding (mirrors the web app's live mode).
    final profile = ride.profile;
    if (profile != null && profile.latitude.isNotEmpty) {
      turns = detectTurns(
        profile.latitude,
        profile.longitude,
        profile.distanceKm,
      );
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

      // Cue list: turns still ahead of the rider (small back-tolerance so a
      // turn doesn't vanish the instant you reach it — matches live.js).
      upcomingTurns = turns
          .where((t) => t.distanceKm >= traveledDistanceKm! - 0.02)
          .take(3)
          .toList();
      nextTurn = upcomingTurns.isEmpty ? null : upcomingTurns.first;
      distanceToNextTurnKm =
          nextTurn == null ? null : nextTurn!.distanceKm - traveledDistanceKm!;
    }
    notifyListeners();
  }

  /// Map position of a turn: the profile coordinate nearest the turn's
  /// distance along the route (turns carry no coordinates of their own).
  LatLng? locationForTurn(Turn turn) {
    final profile = ride.profile;
    if (profile == null || profile.latitude.isEmpty) return null;
    var bestIdx = 0;
    var bestDiff = double.infinity;
    for (var i = 0; i < profile.distanceKm.length; i++) {
      final diff = (profile.distanceKm[i] - turn.distanceKm).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }
    return LatLng(profile.latitude[bestIdx], profile.longitude[bestIdx]);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
