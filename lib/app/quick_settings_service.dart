import 'dart:async';

import 'database/app_database.dart';
import 'database/daos/settings_dao.dart';

/// Service for quick-access settings.
///
/// SSOT-compliant: All settings (including dark_mode) are stored in SQLite.
/// This service preloads dark_mode for instant theme loading at startup.
///
/// The dark_mode value is cached in memory after initialization to avoid
/// synchronous database queries during widget building, while maintaining
/// SQLite as the single source of truth.
class QuickSettingsService {
  QuickSettingsService._();

  static QuickSettingsService? _instance;
  static bool? _darkModeCached;
  static Completer<bool>? _initCompleter;
  static SettingsDao? _settingsDao;

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
  static bool get isInitialized => _instance != null && _darkModeCached != null;

  /// Initialize the service from SQLite database.
  /// Must be called before accessing [instance] or [darkMode].
  /// Returns the initial dark mode value for immediate use in app startup.
  /// Thread-safe: multiple calls will wait for the first initialization.
  static Future<bool> initialize() async {
    // If already initialized, return cached value
    if (_instance != null && _darkModeCached != null) {
      return _darkModeCached!;
    }

    // If initialization is in progress, wait for it
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    // Start initialization
    _initCompleter = Completer<bool>();
    try {
      final database = await AppDatabase.instance;
      _settingsDao = SettingsDao(database);
      _instance = QuickSettingsService._();

      // Load dark_mode from SQLite (defaults to false if not set)
      final darkMode = await _settingsDao!.getBool(SettingsKeys.darkMode) ?? false;
      _darkModeCached = darkMode;

      _initCompleter!.complete(darkMode);
      return darkMode;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Get dark mode from cache (after initialization).
  /// Returns cached value - safe for use in widget build methods.
  /// Always returns a valid value (false if not set).
  bool get darkMode => _darkModeCached ?? false;

  /// Set dark mode and update SQLite immediately.
  /// Updates the in-memory cache for instant UI response.
  Future<void> setDarkMode(bool value) async {
    _darkModeCached = value;
    if (_settingsDao != null) {
      await _settingsDao!.setBool(SettingsKeys.darkMode, value);
    }
  }

  /// Refresh dark_mode from SQLite (internal use).
  /// Call this if external code modifies settings directly.
  Future<void> refreshFromSqlite() async {
    if (_settingsDao != null) {
      _darkModeCached = await _settingsDao!.getBool(SettingsKeys.darkMode);
    }
  }
}
