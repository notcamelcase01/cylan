/// One comment on a public event (`GET /api/events/{id}/comments/`). Flat and
/// unthreaded — no replies, tagging, or editing; a commenter can only delete
/// their own. [user] is the commenter's username, which is also how the app
/// decides whether to offer its delete action (compare against the signed-in
/// username).
class EventComment {
  final int id;
  final String user;
  final String text;
  final DateTime createdAt;

  const EventComment({
    required this.id,
    required this.user,
    required this.text,
    required this.createdAt,
  });

  factory EventComment.fromJson(Map<String, dynamic> json) => EventComment(
        id: json['id'] as int,
        user: json['user'] as String,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class EventCommentPage {
  final int count;
  final String? next;
  final String? previous;
  final List<EventComment> results;

  EventCommentPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  factory EventCommentPage.fromJson(Map<String, dynamic> json) =>
      EventCommentPage(
        count: json['count'] as int,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>)
            .map((e) => EventComment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
