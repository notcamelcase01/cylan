import 'checklist.dart';
import 'event.dart';

/// A rider's subscription to an event (`/api/subscriptions/`), carrying the
/// event it's for (as a summary [Event]) and the [Checklist] the rider chose
/// or created for it (null if they attached none).
class Subscription {
  final int id;
  final Event event;
  final Checklist? checklist;
  final DateTime joinedAt;

  /// **Deprecated / always null.** Copy-on-subscribe was removed and never
  /// replaced with an app-side equivalent. The field is kept only because the
  /// API still returns it (always null) for backwards compatibility; nothing
  /// should read it.
  final EventRide? copiedRide;

  const Subscription({
    required this.id,
    required this.event,
    required this.checklist,
    required this.joinedAt,
    this.copiedRide,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as int,
        event: Event.fromJson(json['event'] as Map<String, dynamic>),
        checklist: json['checklist'] == null
            ? null
            : Checklist.fromJson(json['checklist'] as Map<String, dynamic>),
        joinedAt: DateTime.parse(json['joined_at'] as String),
        copiedRide: json['copied_ride'] == null
            ? null
            : EventRide.fromJson(json['copied_ride'] as Map<String, dynamic>),
      );
}

/// One row of an event's creator-only roster
/// (`GET /api/events/{id}/subscribers/`) — just who joined and when, not a
/// full [Subscription].
class EventSubscriber {
  final String username;
  final DateTime joinedAt;

  const EventSubscriber({required this.username, required this.joinedAt});

  factory EventSubscriber.fromJson(Map<String, dynamic> json) =>
      EventSubscriber(
        username: json['username'] as String,
        joinedAt: DateTime.parse(json['joined_at'] as String),
      );
}

/// The whole roster payload: the [subscribers] plus the cap context
/// ([count] / [maxSubscribers]) so the screen can show "12 / 20 joined".
class EventRoster {
  final int count;
  final int? maxSubscribers;
  final List<EventSubscriber> subscribers;

  const EventRoster({
    required this.count,
    required this.maxSubscribers,
    required this.subscribers,
  });

  factory EventRoster.fromJson(Map<String, dynamic> json) => EventRoster(
        count: json['count'] as int,
        maxSubscribers: json['max_subscribers'] as int?,
        subscribers: (json['subscribers'] as List<dynamic>)
            .map((e) => EventSubscriber.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SubscriptionPage {
  final int count;
  final String? next;
  final String? previous;
  final List<Subscription> results;

  SubscriptionPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory SubscriptionPage.fromJson(Map<String, dynamic> json) =>
      SubscriptionPage(
        count: json['count'] as int,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>)
            .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
