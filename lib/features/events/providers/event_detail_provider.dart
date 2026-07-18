import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/event.dart';

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

  /// True while a subscribe/unsubscribe/delete/document call is in flight, to
  /// disable the buttons that trigger them.
  bool acting = false;

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      event = await _api.getEvent(eventId);
    } on ApiException catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = "Couldn't load this event.";
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Subscribes with an optional checklist. Returns null on success, else a
  /// message. On success the event is reloaded so `is_subscribed` and the
  /// subscriber count refresh.
  Future<String?> subscribe({
    int? checklistId,
    String? newChecklistName,
    List<({String text, bool isMandatory})>? newChecklistItems,
  }) {
    return _act(() => _api.subscribeToEvent(
          eventId,
          checklistId: checklistId,
          newChecklistName: newChecklistName,
          newChecklistItems: newChecklistItems,
        ));
  }

  Future<String?> unsubscribe() {
    return _act(() => _api.unsubscribeFromEvent(eventId));
  }

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
