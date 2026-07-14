import 'package:latlong2/latlong.dart';

/// A notable **climb** or **descent** on a ride, detected and classified on the
/// server (`GET /rides/{id}/sections/`). The app only ever displays these — it
/// never recalculates them.
///
/// Each section is self-contained: it carries its own [coordinates] polyline
/// (same `[lat, lon]` order as the ride profile), so it can be drawn on a map
/// directly. [startIndex]/[endIndex] also index into the ride `profile` arrays
/// (inclusive), which is how the section detail slices out its slice of the
/// elevation/gradient chart.
class RideSection {
  /// `"climb"` or `"descent"` — the stable, machine-readable key.
  final String type;

  /// climb: `moderate`/`steep`/`very_steep`; descent: `steep`/`technical`/`fast`.
  final String category;

  /// Ready-to-show title, e.g. `"Steep climb"`.
  final String label;

  /// Emoji matching the category.
  final String icon;

  final double startKm;
  final double endKm;
  final double distanceKm;

  /// **Signed** — negative for descents.
  final double elevationChangeM;

  /// **Signed** — average grade over the section.
  final double avgGradientPct;

  /// Steepest point (most +ve on a climb, most −ve on a descent).
  final double maxGradientPct;

  /// Sharp turns inside the section (drives `technical`); `0` for climbs.
  final int sharpTurns;

  /// Inclusive indices into the ride `profile` arrays.
  final int startIndex;
  final int endIndex;

  final List<LatLng> coordinates;

  const RideSection({
    required this.type,
    required this.category,
    required this.label,
    required this.icon,
    required this.startKm,
    required this.endKm,
    required this.distanceKm,
    required this.elevationChangeM,
    required this.avgGradientPct,
    required this.maxGradientPct,
    required this.sharpTurns,
    required this.startIndex,
    required this.endIndex,
    required this.coordinates,
  });

  bool get isClimb => type == 'climb';

  factory RideSection.fromJson(Map<String, dynamic> json) {
    double num_(dynamic v) => (v as num).toDouble();
    return RideSection(
      type: json['type'] as String,
      category: json['category'] as String? ?? '',
      label: json['label'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      startKm: num_(json['start_km']),
      endKm: num_(json['end_km']),
      distanceKm: num_(json['distance_km']),
      elevationChangeM: num_(json['elevation_change_m']),
      avgGradientPct: num_(json['avg_gradient_pct']),
      maxGradientPct: num_(json['max_gradient_pct']),
      sharpTurns: (json['sharp_turns'] as num?)?.toInt() ?? 0,
      startIndex: (json['start_index'] as num).toInt(),
      endIndex: (json['end_index'] as num).toInt(),
      coordinates: [
        for (final c in (json['coordinates'] as List<dynamic>? ?? []))
          LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'category': category,
        'label': label,
        'icon': icon,
        'start_km': startKm,
        'end_km': endKm,
        'distance_km': distanceKm,
        'elevation_change_m': elevationChangeM,
        'avg_gradient_pct': avgGradientPct,
        'max_gradient_pct': maxGradientPct,
        'sharp_turns': sharpTurns,
        'start_index': startIndex,
        'end_index': endIndex,
        'coordinates': [
          for (final p in coordinates) [p.latitude, p.longitude],
        ],
      };
}
