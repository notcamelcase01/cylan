import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient.instance;

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? error;
  bool isBusy = false;

  /// Called once at app start: if a token is already stored, validate it
  /// against the server rather than trusting it blindly.
  ///
  /// A stored token is only cleared when the server actually rejects it
  /// (401/403). Any other failure - no connection, timeout, a 5xx - means we
  /// simply couldn't check, so the stored token is kept and the rider stays
  /// logged in; otherwise going offline would sign them out with no way to
  /// log back in until connectivity returns.
  Future<void> tryAutoLogin() async {
    if (!await _api.isLoggedIn) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      currentUser = await _api.me();
      status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _api.logout();
        status = AuthStatus.unauthenticated;
      } else {
        status = AuthStatus.authenticated;
      }
    } catch (_) {
      status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await _api.login(username, password);
      currentUser = await _api.me();
      status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> signup({
    required String username,
    required String password,
    String? name,
    String? email,
  }) async {
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      currentUser = await _api.signup(
        username: username,
        password: password,
        name: name,
        email: email,
      );
      status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Updates the rider's optional profile (name / email). Returns the error
  /// message on failure, or `null` on success.
  Future<String?> updateProfile({String? name, String? email}) async {
    try {
      currentUser = await _api.updateProfile(name: name, email: email);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> logout() async {
    await _api.logout();
    currentUser = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
