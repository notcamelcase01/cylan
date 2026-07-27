import 'package:latlong2/latlong.dart';

const Distance _distance = Distance();

class RideProfile {
  final List<double> distanceKm;
  final List<double> elevationM;
  final List<double> gradientPct;
  final List<double> latitude;
  final List<double> longitude;

  RideProfile({
    required this.distanceKm,
    required this.elevationM,
    required this.gradientPct,
    required this.latitude,
    required this.longitude,
  });

  factory RideProfile.fromJson(Map<String, dynamic> json) {
    List<double> nums(String key) => (json[key] as List<dynamic>? ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    return RideProfile(
      distanceKm: nums('distance_km'),
      elevationM: nums('elevation_m'),
      gradientPct: nums('gradient_pct'),
      latitude: nums('latitude'),
      longitude: nums('longitude'),
    );
  }

  Map<String, dynamic> toJson() => {
        'distance_km': distanceKm,
        'elevation_m': elevationM,
        'gradient_pct': gradientPct,
        'latitude': latitude,
        'longitude': longitude,
      };

  bool get hasTrack => latitude.isNotEmpty;

  /// The route coordinate at [km] along the ride, linearly interpolated from
  /// the parallel distance/lat/lng samples. Clamps to the first/last point for
  /// a [km] outside the ride. Callers must check [hasTrack] first.
  LatLng pointAtKm(double km) {
    final d = distanceKm;
    if (d.isEmpty) return LatLng(latitude.first, longitude.first);
    if (km <= d.first) return LatLng(latitude.first, longitude.first);
    for (var i = 1; i < d.length; i++) {
      if (d[i] >= km) {
        final span = d[i] - d[i - 1];
        final t = span <= 0 ? 0.0 : (km - d[i - 1]) / span;
        return LatLng(
          latitude[i - 1] + (latitude[i] - latitude[i - 1]) * t,
          longitude[i - 1] + (longitude[i] - longitude[i - 1]) * t,
        );
      }
    }
    return LatLng(latitude.last, longitude.last);
  }

  /// How far along the ride [point] sits, as the distance of the nearest
  /// profile sample. The inverse of [pointAtKm], used to place a
  /// tapped-on-the-map control point in route order.
  ///
  /// Resolution is that of the (downsampled) profile rather than exact
  /// perpendicular projection onto each segment — enough to sort control
  /// points and label them "at km 42", which is all it's used for.
  double nearestDistanceKm(LatLng point) {
    if (latitude.isEmpty) return 0;
    var bestIndex = 0;
    var bestMeters = double.infinity;
    for (var i = 0; i < latitude.length; i++) {
      final meters = _distance(point, LatLng(latitude[i], longitude[i]));
      if (meters < bestMeters) {
        bestMeters = meters;
        bestIndex = i;
      }
    }
    return bestIndex < distanceKm.length ? distanceKm[bestIndex] : 0;
  }

  /// Total ride distance per the profile, for bounding a "distance along
  /// route" entry.
  double get totalKm => distanceKm.isEmpty ? 0 : distanceKm.last;
}
