import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/checklist.dart';
import '../../../core/models/event.dart';
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

  /// True while the voluntary "copy this route to my rides" call is in flight.
  /// Separate from [acting] so it only disables its own button (it lives in the
  /// route section, away from the subscribe/document controls).
  bool copyingRide = false;

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

  /// Copies the event's attached route into the rider's own library (the
  /// voluntary action that replaced copy-on-subscribe). Returns the new [Ride]
  /// on success, or a message on failure. Idempotent server-side — copying
  /// twice returns the same ride, never a duplicate.
  Future<({Ride? ride, String? error})> copyRide() async {
    copyingRide = true;
    notifyListeners();
    try {
      final ride = await _api.copyEventRide(eventId);
      return (ride: ride, error: null);
    } on ApiException catch (e) {
      return (ride: null, error: e.message);
    } catch (_) {
      return (ride: null, error: 'Something went wrong. Please try again.');
    } finally {
      copyingRide = false;
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
