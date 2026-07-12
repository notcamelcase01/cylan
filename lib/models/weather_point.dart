class WeatherPoint {
  final double distanceKm;
  final DateTime eta;
  final double latitude;
  final double longitude;
  final DateTime matchedTime;
  final double? temperatureC;
  final double? feelsLikeC;
  final double? precipitationMm;
  final int? humidityPct;
  final double? windKmh;
  final double? windDirectionDeg;
  final String windDirection;
  final String condition;
  final String icon;

  WeatherPoint({
    required this.distanceKm,
    required this.eta,
    required this.latitude,
    required this.longitude,
    required this.matchedTime,
    required this.temperatureC,
    required this.feelsLikeC,
    required this.precipitationMm,
    required this.humidityPct,
    required this.windKmh,
    required this.windDirectionDeg,
    required this.windDirection,
    required this.condition,
    required this.icon,
  });

  factory WeatherPoint.fromJson(Map<String, dynamic> json) {
    double? numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
    return WeatherPoint(
      distanceKm: (json['distance_km'] as num).toDouble(),
      eta: DateTime.parse(json['eta'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      matchedTime: DateTime.parse(json['matched_time'] as String),
      temperatureC: numOrNull(json['temperature_c']),
      feelsLikeC: numOrNull(json['feels_like_c']),
      precipitationMm: numOrNull(json['precipitation_mm']),
      humidityPct: json['humidity_pct'] as int?,
      windKmh: numOrNull(json['wind_kmh']),
      windDirectionDeg: numOrNull(json['wind_direction_deg']),
      windDirection: json['wind_direction'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
    );
  }
}
