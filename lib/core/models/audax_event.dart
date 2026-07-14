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
        'registration_close_date': registrationCloseDate?.toIso8601String(),
        'event_date': eventDate.toIso8601String(),
        'start_point': startPoint,
        'event_fee': eventFee,
        'club_contact_number': clubContactNumber,
        'route_map_url': routeMapUrl,
      };
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
