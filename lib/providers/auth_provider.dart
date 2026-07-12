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
  Future<void> tryAutoLogin() async {
    if (!await _api.isLoggedIn) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      currentUser = await _api.me();
      status = AuthStatus.authenticated;
    } catch (_) {
      await _api.logout();
      status = AuthStatus.unauthenticated;
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
