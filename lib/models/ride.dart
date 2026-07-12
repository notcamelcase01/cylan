import 'ride_profile.dart';

class Ride {
  final int id;
  final String name;
  final String sourceFormat;
  final DateTime? recordedAt;
  final DateTime createdAt;
  final double distanceKm;
  final double distanceM;
  final double totalAscentM;
  final double totalDescentM;
  final double? minElevationM;
  final double? maxElevationM;
  final double netElevationM;
  final double maxGradientPct;
  final double minGradientPct;
  final int pointCount;
  final String? originalFilename;
  final RideProfile? profile;

  Ride({
    required this.id,
    required this.name,
    required this.sourceFormat,
    required this.recordedAt,
    required this.createdAt,
    required this.distanceKm,
    required this.distanceM,
    required this.totalAscentM,
    required this.totalDescentM,
    required this.minElevationM,
    required this.maxElevationM,
    required this.netElevationM,
    required this.maxGradientPct,
    required this.minGradientPct,
    required this.pointCount,
    this.originalFilename,
    this.profile,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    double? numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
    return Ride(
      id: json['id'] as int,
      name: json['name'] as String,
      sourceFormat: json['source_format'] as String,
      recordedAt: json['recorded_at'] == null
          ? null
          : DateTime.parse(json['recorded_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      distanceKm: (json['distance_km'] as num).toDouble(),
      distanceM: (json['distance_m'] as num).toDouble(),
      totalAscentM: (json['total_ascent_m'] as num).toDouble(),
      totalDescentM: (json['total_descent_m'] as num).toDouble(),
      minElevationM: numOrNull(json['min_elevation_m']),
      maxElevationM: numOrNull(json['max_elevation_m']),
      netElevationM: (json['net_elevation_m'] as num).toDouble(),
      maxGradientPct: (json['max_gradient_pct'] as num).toDouble(),
      minGradientPct: (json['min_gradient_pct'] as num).toDouble(),
      pointCount: json['point_count'] as int,
      originalFilename: json['original_filename'] as String?,
      profile: json['profile'] == null
          ? null
          : RideProfile.fromJson(json['profile'] as Map<String, dynamic>),
    );
  }
}

class RidePage {
  final int count;
  final String? next;
  final String? previous;
  final List<Ride> results;

  RidePage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory RidePage.fromJson(Map<String, dynamic> json) => RidePage(
        count: json['count'] as int,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>)
            .map((e) => Ride.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
