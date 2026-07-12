/// A turn along a route, computed on-device from the ride profile
/// (see `services/turn_detection.dart`). Mirrors the web app's turn shape
/// (`{distance_km, direction, kind, angle_deg}`) minus the coordinates —
/// the map position is derived from the profile point nearest [distanceKm].
class Turn {
  final double distanceKm;

  /// `"left"` or `"right"`.
  final String direction;

  /// `"slight"`, `"turn"`, or `"sharp"`.
  final String kind;

  /// Absolute bearing change, in degrees.
  final double angleDeg;

  const Turn({
    required this.distanceKm,
    required this.direction,
    required this.kind,
    required this.angleDeg,
  });

  /// Human label, e.g. `"sharp left"`.
  String get label => '$kind $direction';
}
