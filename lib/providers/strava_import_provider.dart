import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/ride.dart';
import '../models/strava_route.dart';

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
    selectedIds
      ..clear()
      ..addAll(routes.map((r) => r.id));
    step = StravaStep.routes;
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
    } on ApiException catch (e) {
      error = e.message;
      step = StravaStep.routes;
    }
    notifyListeners();
  }
}
