import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_comment.dart';
import '../../../core/models/ride.dart';
import '../../../core/models/subscription.dart';

/// Screen-scoped state for one event's detail view (created per
/// `EventDetailScreen`, like `RidesProvider`/`StravaImportProvider` are per
/// screen — not a global cache). Holds the full [Event] and drives the
/// subscribe / unsubscribe / delete / waiver-document actions.
///
/// Actions return an error message (or null on success) so the screen can
/// SnackBar it and invalidate the shared events-list cache itself, keeping this
/// provider unaware of the list.
class EventDetailProvider extends ChangeNotifier {
  EventDetailProvider({
    required this.eventId,
    Event? initial,
    ApiClient? api,
  })  : _api = api ?? ApiClient.instance,
        event = initial;

  final int eventId;
  final ApiClient _api;

  /// The event — starts as the summary the list already had (if any), then
  /// upgrades to the full detail once [load] completes.
  Event? event;
  bool loading = false;
  String? loadError;

  /// The caller's own subscription to this event, when they have one — carries
  /// the checklist they attached so the detail screen can show and tick it.
  /// Populated on [load] (if already subscribed) and on [subscribe].
  Subscription? mySubscription;

  /// True while a subscribe/unsubscribe/delete/document call is in flight, to
  /// disable the buttons that trigger them.
  bool acting = false;

  /// The event's comments, oldest first, as loaded so far (public events
  /// only). Grows page by page via [loadMoreComments].
  List<EventComment> comments = [];

  /// Total number of comments on the server (the page `count`), which can
  /// exceed [comments.length] until every page is loaded.
  int commentCount = 0;
  bool commentsLoading = false;
  String? commentsError;
  String? _commentsNextUrl;

  /// True while a posted comment is in flight, to disable the send button.
  bool postingComment = false;

  /// Like state for the event's attached ride, kept separately from
  /// [event.ride] — the event payload embeds only a trimmed [EventRide] with
  /// no like info, so this is populated from a full [Ride] fetch instead.
  /// Null until that fetch completes (or if there's no ride to like).
  int? rideLikesCount;
  bool rideIsLiked = false;
  bool likingRide = false;

  bool get hasMoreComments => _commentsNextUrl != null;

  Checklist? get myChecklist => mySubscription?.checklist;

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      event = await _api.getEvent(eventId);
      // If we're already subscribed, pull our subscription so the attached
      // checklist shows without needing to re-subscribe.
      if (event?.isSubscribed == true) {
        await _loadMySubscription();
      } else {
        mySubscription = null;
      }
      // Comments exist on public events only. Not awaited: they have their own
      // loading/error state, and the event detail shouldn't wait on them.
      if (event?.isPublic == true) unawaited(loadComments());
      // Same treatment for the ride's like info: its own fetch, not awaited,
      // only for a public event with a route attached.
      if (event?.isPublic == true && event?.ride != null) {
        unawaited(_loadRideLikeInfo());
      }
    } on ApiException catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = "Couldn't load this event.";
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Finds the caller's subscription for this event among their subscriptions.
  /// Best-effort: a failure here shouldn't fail the whole event load, so it
  /// swallows errors and just leaves [mySubscription] null.
  Future<void> _loadMySubscription() async {
    try {
      String? pageUrl;
      do {
        final page = await _api.listMySubscriptions(pageUrl: pageUrl);
        for (final sub in page.results) {
          if (sub.event.id == eventId) {
            mySubscription = sub;
            return;
          }
        }
        pageUrl = page.next;
      } while (pageUrl != null);
    } catch (_) {
      // Leave mySubscription as-is; the checklist section just won't render.
    }
  }

  /// Fetches the attached ride's full detail just for its like info. Best-effort,
  /// like [_loadMySubscription]: a failure here shouldn't fail the whole event
  /// load, so [rideLikesCount] just stays null and the like button hides.
  Future<void> _loadRideLikeInfo() async {
    final rideId = event?.ride?.id;
    if (rideId == null) return;
    try {
      final ride = await _api.getRide(rideId);
      rideLikesCount = ride.likesCount;
      rideIsLiked = ride.isLiked;
      notifyListeners();
    } catch (_) {
      // Leave rideLikesCount null; the like button just won't render.
    }
  }

  /// Likes/unlikes the event's attached ride. No-op if the like info never
  /// loaded (so there's nothing to flip). Optimistic, like
  /// `RideDetailProvider.toggleLike`: flips immediately, rolls back on failure.
  Future<void> toggleRideLike() async {
    final rideId = event?.ride?.id;
    if (rideId == null || rideLikesCount == null || likingRide) return;
    final wasLiked = rideIsLiked;
    likingRide = true;
    rideIsLiked = !wasLiked;
    notifyListeners();
    try {
      rideLikesCount =
          wasLiked ? await _api.unlikeRide(rideId) : await _api.likeRide(rideId);
    } catch (_) {
      rideIsLiked = wasLiked;
    } finally {
      likingRide = false;
      notifyListeners();
    }
  }

  /// (Re)loads the first page of comments, replacing whatever is shown. Safe
  /// to call again as a retry after [commentsError].
  Future<void> loadComments() async {
    commentsLoading = true;
    commentsError = null;
    notifyListeners();
    try {
      final page = await _api.listEventComments(eventId);
      comments = page.results;
      commentCount = page.count;
      _commentsNextUrl = page.next;
    } on ApiException catch (e) {
      commentsError = e.message;
    } catch (_) {
      commentsError = "Couldn't load comments.";
    } finally {
      commentsLoading = false;
      notifyListeners();
    }
  }

  /// Appends the next page of comments (oldest first, so "more" means newer).
  /// No-op when everything is already loaded or a load is running.
  Future<void> loadMoreComments() async {
    final next = _commentsNextUrl;
    if (next == null || commentsLoading) return;
    commentsLoading = true;
    notifyListeners();
    try {
      final page = await _api.listEventComments(eventId, pageUrl: next);
      // A comment posted from this screen was appended locally and can come
      // back on a later page — drop ids we already show.
      final known = {for (final c in comments) c.id};
      comments = [
        ...comments,
        ...page.results.where((c) => !known.contains(c.id)),
      ];
      commentCount = page.count;
      _commentsNextUrl = page.next;
    } on ApiException catch (e) {
      commentsError = e.message;
    } catch (_) {
      commentsError = "Couldn't load comments.";
    } finally {
      commentsLoading = false;
      notifyListeners();
    }
  }

  /// Posts [text] as a comment. Returns null on success, else a message. On
  /// success the new comment is appended locally (comments run oldest→newest,
  /// so the end is where it belongs) rather than refetching every page.
  Future<String?> postComment(String text) async {
    postingComment = true;
    notifyListeners();
    try {
      final comment = await _api.addEventComment(eventId, text);
      comments = [...comments, comment];
      commentCount += 1;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      postingComment = false;
      notifyListeners();
    }
  }

  /// Deletes the caller's own comment and drops it from the list. Returns null
  /// on success, else a message (`403` if the comment isn't theirs — the UI
  /// only offers delete on own comments, so that's belt-and-braces).
  Future<String?> deleteComment(int commentId) async {
    try {
      await _api.deleteEventComment(commentId);
      comments = [for (final c in comments) if (c.id != commentId) c];
      commentCount = commentCount > 0 ? commentCount - 1 : 0;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return "Couldn't delete the comment.";
    }
  }

  /// Subscribes with an optional checklist. Returns null on success, else a
  /// message. On success the event is reloaded (so `is_subscribed` and the
  /// count refresh) and [mySubscription] is set from the response, so the
  /// attached checklist appears immediately.
  Future<String?> subscribe({
    int? checklistId,
    String? newChecklistName,
    List<({String text, bool isMandatory})>? newChecklistItems,
  }) async {
    acting = true;
    notifyListeners();
    try {
      mySubscription = await _api.subscribeToEvent(
        eventId,
        checklistId: checklistId,
        newChecklistName: newChecklistName,
        newChecklistItems: newChecklistItems,
      );
      event = await _api.getEvent(eventId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  Future<String?> unsubscribe() async {
    acting = true;
    notifyListeners();
    try {
      await _api.unsubscribeFromEvent(eventId);
      mySubscription = null;
      event = await _api.getEvent(eventId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  /// Ticks a checklist item on/off. Optimistically updates the local copy so
  /// the checkbox responds instantly, then reverts if the server rejects it.
  /// Returns null on success, else a message.
  Future<String?> toggleChecklistItem(int itemId, bool isDone) async {
    final checklist = mySubscription?.checklist;
    if (checklist == null) return null;
    final previous = checklist;
    // Optimistic update.
    mySubscription = _withChecklist(checklist.withItems([
      for (final it in checklist.items)
        it.id == itemId ? it.copyWith(isDone: isDone) : it,
    ]));
    notifyListeners();
    try {
      await _api.updateChecklistItem(itemId, isDone: isDone);
      return null;
    } on ApiException catch (e) {
      mySubscription = _withChecklist(previous);
      notifyListeners();
      return e.message;
    } catch (_) {
      mySubscription = _withChecklist(previous);
      notifyListeners();
      return "Couldn't update the item.";
    }
  }

  Subscription _withChecklist(Checklist checklist) => Subscription(
        id: mySubscription!.id,
        event: mySubscription!.event,
        checklist: checklist,
        joinedAt: mySubscription!.joinedAt,
        copiedRide: mySubscription!.copiedRide,
      );

  Future<String?> uploadDocument(
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) {
    return _act(() async {
      final presign = await _api.presignEventDocument(eventId);
      await _api.uploadEventDocument(presign, filePath, onProgress: onProgress);
      event = await _api.confirmEventDocument(eventId);
    }, reload: false);
  }

  Future<String?> deleteDocument() {
    return _act(() => _api.deleteEventDocument(eventId));
  }

  /// Deletes the whole event. Doesn't reload (there's nothing to reload);
  /// the screen pops on success.
  Future<String?> deleteEvent() async {
    acting = true;
    notifyListeners();
    try {
      await _api.deleteEvent(eventId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  /// Fetches a fresh short-lived URL to view the waiver PDF. Returns the URL,
  /// or throws [ApiException] for the caller to surface (kept as a throw here
  /// because the caller wants the URL, not a success flag).
  Future<String> documentUrl() => _api.getEventDocumentUrl(eventId);

  /// Runs [action], then (unless [reload] is false) reloads the event so the
  /// UI reflects the server's new state. Returns null on success, else a
  /// message.
  Future<String?> _act(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    acting = true;
    notifyListeners();
    try {
      await action();
      if (reload) event = await _api.getEvent(eventId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      acting = false;
      notifyListeners();
    }
  }
}
