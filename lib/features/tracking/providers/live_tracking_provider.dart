import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/models/ride.dart';
import '../services/location_service.dart';

class LiveTrackingProvider extends ChangeNotifier {
  final Ride ride;

  /// Defaults to the real one, so callers say `LiveTrackingProvider(ride)`.
  /// Tests pass a fake to drive the orderings that matter here — leaving the
  /// screen while the permission prompt is still open, and a GPS feed that
  /// errors — neither of which can be staged against a real receiver.
  LiveTrackingProvider(this.ride, {LocationService? locationService})
      : _locationService = locationService ?? LocationService();

  final LocationService _locationService;
  StreamSubscription<Position>? _positionSub;

  /// How long to wait for the first fix before saying so. Long enough that a
  /// receiver warming up normally never trips it; short enough that a rider
  /// isn't left guessing.
  static const _firstFixGrace = Duration(seconds: 10);
  Timer? _firstFixTimer;

  /// Whether the screen that owns this has already gone away. [start] waits on
  /// the OS permission prompt, which the rider can leave sitting open for as
  /// long as they like — and back out of — so by the time it returns, this
  /// provider may be long disposed.
  bool _disposed = false;

  Position? position;

  /// Straight-line distance from the ride's starting point to the current
  /// GPS fix — not distance traveled along the route (which would need
  /// matching the fix to a point on the route, unreliable on routes that
  /// cross or double back on themselves).
  double? distanceFromStartKm;
  double? offRouteMeters;

  bool isLoading = false;
  String? error;
  String? permissionMessage;

  /// A problem with the GPS feed that isn't worth throwing the screen away
  /// over. Shown as a note *over* the route rather than instead of it: the map
  /// is still worth looking at while the receiver sorts itself out, and these
  /// are usually temporary. Cleared by the next fix.
  ///
  /// Deliberately not [error], which replaces the whole screen — losing the
  /// route mid-ride because the signal dipped under a bridge would be a wildly
  /// disproportionate response.
  String? gpsMessage;

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
    _positionSub = _locationService.positionStream().listen(
      _onPosition,
      onError: _onPositionError,
    );

    // A fix that simply never arrives is silent: the stream reports nothing,
    // because there's nothing to report. Core Location's own "can't get a fix"
    // (kCLErrorLocationUnknown) doesn't reach us either — geolocator logs and
    // swallows it, per Apple's guidance that it's transient. So without this
    // the rider watches a map whose dot never appears, with nothing on screen
    // to say whether it's still trying. Common on a Mac, which has no GPS and
    // triangulates from surrounding wifi it may not recognise.
    _firstFixTimer?.cancel();
    _firstFixTimer = Timer(_firstFixGrace, () {
      if (_disposed || position != null) return;
      gpsMessage = 'Still waiting for a location fix…';
      notifyListeners();
    });
  }

  /// The GPS feed itself failing, as opposed to failing to start.
  ///
  /// Core Location's "no fix right now" (`kCLErrorLocationUnknown`) never
  /// reaches here — geolocator logs it and swallows it, since Apple documents
  /// it as transient. What does reach here is the rest: the receiver failing,
  /// or location being switched off mid-ride. Without an `onError` those went
  /// to the zone unhandled and the rider just watched a map whose dot never
  /// moved, with nothing on screen to say why.
  ///
  /// The subscription is left alive on purpose — the feed often recovers, and
  /// [_onPosition] clears this the moment it does.
  void _onPositionError(Object e) {
    if (_disposed) return;
    gpsMessage = 'Lost the GPS signal — trying to reconnect.';
    notifyListeners();
  }

  void _onPosition(Position pos) {
    // A fix arrived, so whatever the receiver was complaining about is over.
    gpsMessage = null;
    _firstFixTimer?.cancel();
    position = pos;
    final profile = ride.profile;
    if (profile != null && profile.latitude.isNotEmpty) {
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
        }
      }
      offRouteMeters = bestMeters;
      distanceFromStartKm = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            profile.latitude.first,
            profile.longitude.first,
          ) /
          1000;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _firstFixTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}
