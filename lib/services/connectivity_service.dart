import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';

/// Tracks whether the app can currently reach the Cylan server, so an offline
/// view can offer to switch back to the live (online) experience.
///
/// This is entirely event-driven — there is no polling. It checks once on
/// [start], then listens to the OS connectivity-change stream. A wifi/cellular
/// interface only being *present* doesn't prove the internet works (captive
/// portals, dead links), so each time an interface appears we confirm with a
/// single lightweight request to the server; any HTTP response counts as
/// reachable, a socket error / timeout counts as not.
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _online = false;
  bool get online => _online;

  static const _pingTimeout = Duration(seconds: 5);

  void start() {
    _evaluate();
    _sub = _connectivity.onConnectivityChanged.listen(_evaluate);
  }

  /// [results] is passed for a change event; omitted for the initial check
  /// (where we ask for the current state once).
  Future<void> _evaluate([List<ConnectivityResult>? results]) async {
    final current = results ?? await _connectivity.checkConnectivity();
    final hasInterface =
        current.any((r) => r != ConnectivityResult.none);
    if (!hasInterface) {
      _setOnline(false);
      return;
    }
    _setOnline(await _serverReachable());
  }

  /// A single HEAD request to the API base. We don't care about the status
  /// code — merely getting a response means we reached the server over the
  /// internet; a [SocketException]/timeout means we didn't.
  Future<bool> _serverReachable() async {
    try {
      await http
          .head(Uri.parse(ApiClient.baseUrl))
          .timeout(_pingTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setOnline(bool value) {
    if (value != _online) {
      _online = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
