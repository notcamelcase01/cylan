import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the app's light/dark/system preference and persists it, so the
/// choice survives restarts (mirrors the web app's theme toggle).
class ThemeProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    // Best-effort, like every other read of this store (see [ApiClient.token]):
    // a keystore that won't answer is not a reason to throw out of a
    // constructor on every launch. An unreadable preference is just the
    // default one.
    String? stored;
    try {
      stored = await _storage.read(key: _key);
    } catch (_) {
      return; // stays on ThemeMode.system, which is already set
    }
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  /// Cycle light → dark → system, persisting the new choice.
  Future<void> cycle() async {
    _mode = switch (_mode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    notifyListeners();
    try {
      await _storage.write(key: _key, value: _mode.name);
    } catch (_) {
      // The toggle already took effect; it just won't outlive the app.
    }
  }

  /// The icon representing the *current* mode.
  IconData get icon => switch (_mode) {
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
        ThemeMode.system => Icons.brightness_auto,
      };

  String get label => switch (_mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };
}
