/// An app-native, user-created event (`/api/events/`). Distinct from the
/// read-only Audax calendar — this is something a rider creates, others
/// subscribe to, and only the creator can edit.
///
/// One class covers both the list ("summary") and detail payloads: the server
/// returns the summary fields everywhere and adds the detail-only fields
/// ([ride], [description], … [isSubscribed]) only on `GET /events/{id}/`,
/// mirroring how [Ride.profile] is null on list responses. Those fields are
/// nullable here and populated only when a detail payload is parsed — check
/// [isDetail] before relying on them.
///
/// The API's enum-like fields ([status], [visibility], [currency],
/// [eventType]) stay plain strings, matching `Ride.sourceFormat` /
/// `AudaxEvent.category` — the server owns the value space and can grow it
/// without an app change, so they're never parsed into a closed Dart enum.
class Event {
  // --- summary fields (always present) ---
  final int id;
  final String name;

  /// Creator's username.
  final String creator;
  final String eventType;

  /// `PRIVATE` | `PUBLIC`.
  final String visibility;

  /// `DRAFT` | `PUBLISHED` | `CANCELLED` | `COMPLETED`.
  final String status;
  final DateTime startDate;

  /// Already resolved server-side: the creator's value, else the attached
  /// ride's start, else `"Ride not added"`.
  final String assemblyPoint;

  /// A Google Maps link, set **only** when [assemblyPoint] is bare
  /// ride-derived coordinates with no label to show instead; null otherwise.
  final String? assemblyPointMapUrl;

  /// `0` means free (there's no separate paid flag — see [isPaid]).
  final double entryFee;
  final String currency;

  /// `null` = unlimited.
  final int? maxSubscribers;
  final int subscriberCount;
  final bool isFull;

  /// Whether a waiver PDF is attached.
  final bool hasDocument;
  final DateTime createdAt;

  // --- detail-only fields (null on summary payloads) ---

  /// True when this was parsed from a detail payload, so the fields below are
  /// meaningful (rather than merely absent).
  final bool isDetail;

  /// The attached ride, trimmed to a mini shape ([EventRide]); null when no
  /// ride is attached.
  final EventRide? ride;
  final String? description;
  final String? contactNumber;
  final String? contactEmail;

  /// `USER_SET` | `FROM_RIDE` | `UNSET`.
  final String? assemblyPointSource;
  final String? remarksTos;
  final List<String>? externalLinks;
  final bool? isPublic;
  final bool? isPaid;

  /// Whether *you* are subscribed.
  final bool? isSubscribed;

  const Event({
    required this.id,
    required this.name,
    required this.creator,
    required this.eventType,
    required this.visibility,
    required this.status,
    required this.startDate,
    required this.assemblyPoint,
    required this.assemblyPointMapUrl,
    required this.entryFee,
    required this.currency,
    required this.maxSubscribers,
    required this.subscriberCount,
    required this.isFull,
    required this.hasDocument,
    required this.createdAt,
    this.isDetail = false,
    this.ride,
    this.description,
    this.contactNumber,
    this.contactEmail,
    this.assemblyPointSource,
    this.remarksTos,
    this.externalLinks,
    this.isPublic,
    this.isPaid,
    this.isSubscribed,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    // The detail-only fields are added as a block by EventDetailSerializer, so
    // any one of them signals a detail payload; `ride` can legitimately be
    // null even then, so key off `description` which detail always carries.
    final isDetail = json.containsKey('description');
    return Event(
      id: json['id'] as int,
      name: json['name'] as String,
      creator: json['creator'] as String,
      eventType: json['event_type'] as String,
      visibility: json['visibility'] as String,
      status: json['status'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      assemblyPoint: json['assembly_point'] as String,
      assemblyPointMapUrl: json['assembly_point_map_url'] as String?,
      entryFee: (json['entry_fee'] as num).toDouble(),
      currency: json['currency'] as String,
      maxSubscribers: json['max_subscribers'] as int?,
      subscriberCount: json['subscriber_count'] as int,
      isFull: json['is_full'] as bool,
      hasDocument: json['has_document'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      isDetail: isDetail,
      ride: json['ride'] == null
          ? null
          : EventRide.fromJson(json['ride'] as Map<String, dynamic>),
      description: json['description'] as String?,
      contactNumber: json['contact_number'] as String?,
      contactEmail: json['contact_email'] as String?,
      assemblyPointSource: json['assembly_point_source'] as String?,
      remarksTos: json['remarks_tos'] as String?,
      externalLinks: json['external_links'] == null
          ? null
          : (json['external_links'] as List<dynamic>)
              .map((e) => e.toString())
              .toList(),
      isPublic: json['is_public'] as bool?,
      isPaid: json['is_paid'] as bool?,
      isSubscribed: json['is_subscribed'] as bool?,
    );
  }
}

/// The attached ride as embedded in an event payload — the server sends only
/// this trimmed subset (`RideMiniSerializer`), not the full [Ride].
class EventRide {
  final int id;
  final String name;
  final double distanceKm;
  final String? location;
  final double? startLatitude;
  final double? startLongitude;

  const EventRide({
    required this.id,
    required this.name,
    required this.distanceKm,
    required this.location,
    required this.startLatitude,
    required this.startLongitude,
  });

  factory EventRide.fromJson(Map<String, dynamic> json) {
    double? numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
    return EventRide(
      id: json['id'] as int,
      name: json['name'] as String,
      distanceKm: (json['distance_km'] as num).toDouble(),
      location: json['location'] as String?,
      startLatitude: numOrNull(json['start_latitude']),
      startLongitude: numOrNull(json['start_longitude']),
    );
  }
}

class EventPage {
  final int count;
  final String? next;
  final String? previous;
  final List<Event> results;

  EventPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory EventPage.fromJson(Map<String, dynamic> json) => EventPage(
        count: json['count'] as int,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>)
            .map((e) => Event.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The event lifecycle values the API accepts, for building a status picker —
/// the server owns the canonical set (`EventStatus`); this mirrors it for UI.
const List<String> kEventStatuses = [
  'DRAFT',
  'PUBLISHED',
  'CANCELLED',
  'COMPLETED',
];

const List<String> kEventVisibilities = ['PRIVATE', 'PUBLIC'];

const List<String> kEventCurrencies = ['INR', 'USD', 'EUR'];
