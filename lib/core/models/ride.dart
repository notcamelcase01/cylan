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

  /// `PRIVATE` | `PUBLIC`. **Read-only, derived server-side**: a ride is
  /// `PUBLIC` while at least one PUBLIC event has it attached (then anyone can
  /// view it), `PRIVATE` otherwise. Never sent back on writes — see the API's
  /// RideVisibility.
  final String visibility;
  final String? originalFilename;
  final RideProfile? profile;
  final double smoothingWindowM;

  /// `NONE` | `PENDING` | `COMPLETED` — the curated-suggestion opt-in flag.
  /// **Read-only, derived server-side**, like [visibility] — see
  /// `POST`/`DELETE /rides/{id}/suggest/` in the API's events.md.
  final String publicSuggestionStatus;

  /// The rider's optional note from opting in, set via `POST .../suggest/`.
  /// Blank if never submitted.
  final String description;

  bool get isPublic => visibility == 'PUBLIC';
  bool get isSuggested => publicSuggestionStatus != 'NONE';
  bool get isSuggestionPending => publicSuggestionStatus == 'PENDING';
  bool get isSuggestionApproved => publicSuggestionStatus == 'COMPLETED';

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
    this.visibility = 'PRIVATE',
    this.originalFilename,
    this.profile,
    this.smoothingWindowM = 30.0,
    this.publicSuggestionStatus = 'NONE',
    this.description = '',
  });

  /// A copy with [publicSuggestionStatus] overridden — used to patch a ride's
  /// suggestion status locally after `suggest`/`unsuggest` without refetching.
  Ride copyWith({String? publicSuggestionStatus}) => Ride(
        id: id,
        name: name,
        sourceFormat: sourceFormat,
        recordedAt: recordedAt,
        createdAt: createdAt,
        distanceKm: distanceKm,
        distanceM: distanceM,
        totalAscentM: totalAscentM,
        totalDescentM: totalDescentM,
        minElevationM: minElevationM,
        maxElevationM: maxElevationM,
        netElevationM: netElevationM,
        maxGradientPct: maxGradientPct,
        minGradientPct: minGradientPct,
        pointCount: pointCount,
        visibility: visibility,
        originalFilename: originalFilename,
        profile: profile,
        smoothingWindowM: smoothingWindowM,
        publicSuggestionStatus: publicSuggestionStatus ?? this.publicSuggestionStatus,
        description: description,
      );

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
      visibility: json['visibility'] as String? ?? 'PRIVATE',
      originalFilename: json['original_filename'] as String?,
      profile: json['profile'] == null
          ? null
          : RideProfile.fromJson(json['profile'] as Map<String, dynamic>),
      smoothingWindowM: numOrNull(json['smoothing_window_m']) ?? 30.0,
      publicSuggestionStatus: json['public_suggestion_status'] as String? ?? 'NONE',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source_format': sourceFormat,
        'recorded_at': recordedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'distance_km': distanceKm,
        'distance_m': distanceM,
        'total_ascent_m': totalAscentM,
        'total_descent_m': totalDescentM,
        'min_elevation_m': minElevationM,
        'max_elevation_m': maxElevationM,
        'net_elevation_m': netElevationM,
        'max_gradient_pct': maxGradientPct,
        'min_gradient_pct': minGradientPct,
        'point_count': pointCount,
        'visibility': visibility,
        'original_filename': originalFilename,
        'profile': profile?.toJson(),
        'smoothing_window_m': smoothingWindowM,
        'public_suggestion_status': publicSuggestionStatus,
        'description': description,
      };
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
