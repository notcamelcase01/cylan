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
}
