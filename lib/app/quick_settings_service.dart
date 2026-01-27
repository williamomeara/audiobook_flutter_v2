import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Service for quick-access settings stored in SharedPreferences.
///
/// ONLY dark_mode is stored here for instant theme loading at startup.
/// All other settings are stored in SQLite via SettingsDao.
///
/// This class provides synchronous access to dark_mode after initial load,
/// which is critical for avoiding theme flash at app startup.
class QuickSettingsService {
  QuickSettingsService._();

  static QuickSettingsService? _instance;
  static SharedPreferences? _prefs;
  static Completer<bool>? _initCompleter;

  /// Key for dark mode setting.
  static const String _keyDarkMode = 'dark_mode';

  /// Get singleton instance. Call [initialize] first.
  static QuickSettingsService get instance {
    if (_instance == null) {
      throw StateError(
        'QuickSettingsService not initialized. Call QuickSettingsService.initialize() first.',
      );
    }
    return _instance!;
  }

  /// Check if service is initialized.
  static bool get isInitialized => _instance != null && _prefs != null;

  /// Initialize the service. Must be called before accessing [instance].
  /// Returns the initial dark mode value for immediate use.
  /// Thread-safe: multiple calls will wait for the first initialization to complete.
  static Future<bool> initialize() async {
    // If already initialized, return current value
    if (_instance != null && _prefs != null) {
      return _prefs!.getBool(_keyDarkMode) ?? false;
    }

    // If initialization is in progress, wait for it
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    // Start initialization
    _initCompleter = Completer<bool>();
    try {
      _prefs = await SharedPreferences.getInstance();
      _instance = QuickSettingsService._();
      final darkMode = _prefs!.getBool(_keyDarkMode) ?? false;
      _initCompleter!.complete(darkMode);
      return darkMode;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Get dark mode synchronously (after initialization).
  bool get darkMode => _prefs?.getBool(_keyDarkMode) ?? false;

  /// Set dark mode. Updates SharedPreferences immediately.
  /// Call SettingsDao.setBool() separately to sync to SQLite.
  Future<void> setDarkMode(bool value) async {
    await _prefs?.setBool(_keyDarkMode, value);
  }

  /// Sync dark mode from SQLite to SharedPreferences.
  /// Call this during migration or if SQLite is the source of truth.
  Future<void> syncFromSqlite(bool? sqliteValue) async {
    if (sqliteValue != null) {
      await _prefs?.setBool(_keyDarkMode, sqliteValue);
    }
  }
}
