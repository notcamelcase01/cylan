/// A saved Strava route the athlete can import, as returned by
/// `GET /api/strava/routes/`. Ids are strings (Strava ids exceed JS/Dart
/// safe-integer range).
class StravaRoute {
  final String id;
  final String name;
  final double? distanceM;
  final double? elevationGainM;
  final int? estimatedMovingTimeS;

  /// Strava activity type code: 1 = ride, 2 = run.
  final int? type;

  const StravaRoute({
    required this.id,
    required this.name,
    this.distanceM,
    this.elevationGainM,
    this.estimatedMovingTimeS,
    this.type,
  });

  double get distanceKm => (distanceM ?? 0) / 1000.0;

  factory StravaRoute.fromJson(Map<String, dynamic> json) {
    double? numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
    return StravaRoute(
      id: json['id'].toString(),
      name: (json['name'] as String?) ?? 'Untitled route',
      distanceM: numOrNull(json['distance_m']),
      elevationGainM: numOrNull(json['elevation_gain_m']),
      estimatedMovingTimeS: (json['estimated_moving_time_s'] as num?)?.toInt(),
      type: (json['type'] as num?)?.toInt(),
    );
  }
}
