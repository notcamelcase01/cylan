import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/ride.dart';
import '../../../core/models/strava_route.dart';

/// Steps of the Strava import flow.
enum StravaStep {
  /// Deciding whether the user is already connected.
  checking,

  /// Not connected — show the "Connect Strava" call to action.
  connect,

  /// Consent opened in the browser; waiting for the user to come back.
  awaitingConsent,

  /// Connected — the route picker is shown.
  routes,

  /// Importing selected routes.
  importing,

  /// Import finished — show a summary.
  done,
}

class StravaImportProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  StravaStep step = StravaStep.checking;
  String? error;

  List<StravaRoute> routes = [];
  final Set<String> selectedIds = {};

  List<Ride> imported = [];
  List<String> failures = [];

  /// Whether the Strava link has already been dropped (via a successful
  /// import, which disconnects by default, or an explicit cancel).
  bool _disconnected = false;

  StravaImportProvider() {
    refreshStatus();
  }

  bool get isSelected => selectedIds.isNotEmpty;

  void toggle(String routeId) {
    if (!selectedIds.remove(routeId)) selectedIds.add(routeId);
    notifyListeners();
  }

  /// Checks whether Strava is already linked; loads routes if so.
  Future<void> refreshStatus() async {
    error = null;
    try {
      if (await _api.stravaConnected()) {
        await _loadRoutes();
      } else {
        step = StravaStep.connect;
      }
    } on ApiException catch (e) {
      error = e.message;
      step = StravaStep.connect;
    }
    notifyListeners();
  }

  /// Opens the Strava consent page in the browser.
  Future<void> connect() async {
    error = null;
    try {
      final url = await _api.stravaAuthorizeUrl();
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        error = "Couldn't open the browser to connect Strava.";
        notifyListeners();
        return;
      }
      step = StravaStep.awaitingConsent;
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  /// Called when the user returns to the app after consenting. Polls status
  /// and moves to the route picker once the link exists.
  Future<void> checkAfterConsent() async {
    if (step != StravaStep.awaitingConsent) return;
    try {
      if (await _api.stravaConnected()) {
        await _loadRoutes();
        notifyListeners();
      }
    } on ApiException {
      // Stay on the waiting screen; the user can retry.
    }
  }

  Future<void> _loadRoutes() async {
    routes = await _api.stravaRoutes();
    selectedIds.clear();
    step = StravaStep.routes;
  }

  /// Ends the Strava connection without importing anything, freeing the
  /// athlete slot for other users.
  Future<void> cancelImport() async {
    try {
      await _api.stravaDisconnect();
      _disconnected = true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
    }
  }

  Future<void> importSelected() async {
    if (selectedIds.isEmpty) return;
    step = StravaStep.importing;
    error = null;
    notifyListeners();
    final chosen = routes.where((r) => selectedIds.contains(r.id)).toList();
    try {
      final result = await _api.stravaImport(chosen);
      imported = result.imported;
      failures = result.failures;
      step = StravaStep.done;
      _disconnected = true; // the import call disconnects by default
    } on ApiException catch (e) {
      error = e.message;
      step = StravaStep.routes;
    }
    notifyListeners();
  }

  /// Best-effort cleanup for when the user leaves the flow without
  /// finishing it — back button, swipe-back, or closing the screen — so a
  /// route was never picked and the athlete slot is left occupied. Safe to
  /// call even when there's no active link; the backend delete is a no-op.
  Future<void> disconnectOnExit() async {
    if (_disconnected) return;
    if (step == StravaStep.checking || step == StravaStep.connect) return;
    if (step == StravaStep.importing) return;
    _disconnected = true;
    try {
      await _api.stravaDisconnect();
    } catch (_) {
      // The screen is already gone; nothing more we can do here.
    }
  }
}
