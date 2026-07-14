/// A single event from the public Audax India brevet calendar
/// (`GET /audax-events/`). Read-only, refreshed server-side only — the app
/// never recalculates or merges these.
///
/// Only [audaxId] and [eventDate] are guaranteed non-null; everything else
/// can be `null` when the source site didn't have it, and should render as a
/// placeholder rather than being hidden.
class AudaxEvent {
  final String audaxId;
  final String? club;
  final String? audaxPageUrl;

  /// Distance/category, same value space as the `category` filter (e.g.
  /// `200`, `1200`, `Fleche`). An **opaque string, not a number** —
  /// non-numeric values are normal and new ones can appear without an API
  /// change, so never hardcode the set or parse it as an int.
  final String? category;

  final DateTime? registrationCloseDate;
  final DateTime eventDate;
  final String? startPoint;
  final double? eventFee;
  final String? clubContactNumber;
  final String? routeMapUrl;

  const AudaxEvent({
    required this.audaxId,
    required this.club,
    required this.audaxPageUrl,
    required this.category,
    required this.registrationCloseDate,
    required this.eventDate,
    required this.startPoint,
    required this.eventFee,
    required this.clubContactNumber,
    required this.routeMapUrl,
  });

  factory AudaxEvent.fromJson(Map<String, dynamic> json) {
    double? numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
    DateTime? dateOrNull(dynamic v) =>
        v == null ? null : DateTime.parse(v as String);
    return AudaxEvent(
      audaxId: json['audax_id'] as String,
      club: json['club'] as String?,
      audaxPageUrl: json['audax_page_url'] as String?,
      category: json['category'] as String?,
      registrationCloseDate: dateOrNull(json['registration_close_date']),
      eventDate: DateTime.parse(json['event_date'] as String),
      startPoint: json['start_point'] as String?,
      eventFee: numOrNull(json['event_fee']),
      clubContactNumber: json['club_contact_number'] as String?,
      routeMapUrl: json['route_map_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'audax_id': audaxId,
        'club': club,
        'audax_page_url': audaxPageUrl,
        'category': category,
        'registration_close_date': registrationCloseDate?.toIso8601String(),
        'event_date': eventDate.toIso8601String(),
        'start_point': startPoint,
        'event_fee': eventFee,
        'club_contact_number': clubContactNumber,
        'route_map_url': routeMapUrl,
      };
}

/// Filter values currently in use (`GET /audax-events/filters/`) — the app
/// builds the category/state/city picker UI from this instead of hardcoding
/// a list, since the source calendar adds categories over time (e.g. `1200`,
/// `Fleche`). `categories` arrives pre-sorted (numeric-then-alphabetical);
/// `states`/`cities` arrive alphabetical — use the arrays as-is.
class AudaxEventFilters {
  final List<String> categories;
  final List<String> states;
  final List<String> cities;

  const AudaxEventFilters({
    required this.categories,
    required this.states,
    required this.cities,
  });

  factory AudaxEventFilters.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic v) =>
        (v as List<dynamic>).map((e) => e as String).toList();
    return AudaxEventFilters(
      categories: strings(json['categories']),
      states: strings(json['states']),
      cities: strings(json['cities']),
    );
  }
}

class AudaxEventPage {
  final int count;
  final String? next;
  final String? previous;
  final List<AudaxEvent> results;

  AudaxEventPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory AudaxEventPage.fromJson(Map<String, dynamic> json) => AudaxEventPage(
        count: json['count'] as int,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>)
            .map((e) => AudaxEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
