/// A curated route suggested during event creation
/// (`GET /api/events/suggestions/`). These come from a staff-reviewed pool, so
/// [terrainLabel] / [elevationRemarks] are ready to display as-is.
///
/// [distanceFromUserKm] is populated only on the radius path (`lat`+`lng`); on
/// the `city` fallback it's null.
class RouteSuggestion {
  final int id;
  final String name;
  final double distanceKm;
  final String? location;

  /// Machine-readable terrain bucket (e.g. `rolling`); [terrainLabel] is its
  /// display form.
  final String terrainClass;
  final String terrainLabel;
  final String elevationRemarks;
  final double? startLatitude;
  final double? startLongitude;
  final double? distanceFromUserKm;

  const RouteSuggestion({
    required this.id,
    required this.name,
    required this.distanceKm,
    required this.location,
    required this.terrainClass,
    required this.terrainLabel,
    required this.elevationRemarks,
    required this.startLatitude,
    required this.startLongitude,
    required this.distanceFromUserKm,
  });

  factory RouteSuggestion.fromJson(Map<String, dynamic> json) {
    double? numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
    return RouteSuggestion(
      id: json['id'] as int,
      name: json['name'] as String,
      distanceKm: (json['distance_km'] as num).toDouble(),
      location: json['location'] as String?,
      terrainClass: json['terrain_class'] as String,
      terrainLabel: json['terrain_label'] as String,
      elevationRemarks: json['elevation_remarks'] as String,
      startLatitude: numOrNull(json['start_latitude']),
      startLongitude: numOrNull(json['start_longitude']),
      distanceFromUserKm: numOrNull(json['distance_from_user_km']),
    );
  }
}

/// The suggestions response: [mode] is `"radius"` or `"city"`, telling the UI
/// which path answered (and hence whether [RouteSuggestion.distanceFromUserKm]
/// is meaningful).
class SuggestionsResult {
  final String mode;
  final int count;
  final List<RouteSuggestion> suggestions;

  const SuggestionsResult({
    required this.mode,
    required this.count,
    required this.suggestions,
  });

  factory SuggestionsResult.fromJson(Map<String, dynamic> json) =>
      SuggestionsResult(
        mode: json['mode'] as String,
        count: json['count'] as int,
        suggestions: (json['suggestions'] as List<dynamic>)
            .map((e) => RouteSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
