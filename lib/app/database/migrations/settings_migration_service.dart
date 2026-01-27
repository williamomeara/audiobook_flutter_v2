import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../daos/settings_dao.dart';

/// Service to migrate settings from SharedPreferences to SQLite.
///
/// This is a one-time migration that runs on app startup. It:
/// 1. Checks if migration is needed (old SP keys exist, migration not done)
/// 2. Reads all settings from SharedPreferences
/// 3. Writes them to SQLite via SettingsDao
/// 4. Clears old SP keys (except dark_mode which stays in SP for instant load)
/// 5. Marks migration as complete
class SettingsMigrationService {
  // Migration flag key
  static const String _migrationDoneKey = 'settings_migration_v4_done';

  // Keys to migrate from SharedPreferences to SQLite
  static const List<String> _keysToMigrate = [
    'selected_voice',
    'auto_advance_chapters',
    'default_playback_rate',
    'smart_synthesis_enabled',
    'cache_quota_gb',
    'show_book_cover_background',
    'haptic_feedback_enabled',
    'synthesis_mode',
    'show_buffer_indicator',
    'compress_on_synthesize',
    'runtime_playback_config_v1', // RuntimePlaybackConfig JSON blob
  ];

  // Keys to clear after migration (NOT dark_mode - it stays in SP)
  static const List<String> _keysToClear = [
    'selected_voice',
    'auto_advance_chapters',
    'default_playback_rate',
    'smart_synthesis_enabled',
    'cache_quota_gb',
    'show_book_cover_background',
    'haptic_feedback_enabled',
    'synthesis_mode',
    'show_buffer_indicator',
    'compress_on_synthesize',
    'runtime_playback_config_v1',
    // Legacy keys from older versions
    'darkMode', // Old camelCase key
    'selectedVoice',
    'autoAdvanceChapters',
    'defaultPlaybackRate',
    'smartSynthesisEnabled',
  ];

  /// Check if migration is needed.
  static Future<bool> needsMigration(Database db) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if already migrated
    if (prefs.getBool(_migrationDoneKey) == true) {
      return false;
    }

    // Check if any old keys exist
    for (final key in _keysToMigrate) {
      if (prefs.containsKey(key)) {
        return true;
      }
    }

    // No old keys - mark as done anyway to skip future checks
    await prefs.setBool(_migrationDoneKey, true);
    return false;
  }

  /// Migrate settings from SharedPreferences to SQLite.
  /// Returns the number of settings migrated.
  static Future<int> migrate(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsDao = SettingsDao(db);
    var count = 0;

    developer.log(
      '🔄 Starting settings migration from SharedPreferences to SQLite',
      name: 'SettingsMigrationService',
    );

    // Migrate each setting
    for (final key in _keysToMigrate) {
      if (!prefs.containsKey(key)) continue;

      try {
        final value = _getPrefsValue(prefs, key);
        if (value != null) {
          // Map old keys to new SQLite keys
          final sqliteKey = _mapKey(key);
          await settingsDao.setSetting(sqliteKey, value);
          count++;

          developer.log(
            '  ✅ Migrated: $key -> $sqliteKey',
            name: 'SettingsMigrationService',
          );
        }
      } catch (e) {
        developer.log(
          '  ⚠️ Failed to migrate $key: $e',
          name: 'SettingsMigrationService',
        );
        // Skip this setting and continue with others
        continue;
      }
    }

    // Migrate dark_mode to SQLite as well (but keep in SP for instant load)
    final darkMode = prefs.getBool('dark_mode') ?? prefs.getBool('darkMode');
    if (darkMode != null) {
      await settingsDao.setSetting('dark_mode', darkMode);
      count++;
      developer.log(
        '  ✅ Migrated dark_mode (also kept in SharedPreferences)',
        name: 'SettingsMigrationService',
      );
    }

    // Clear old keys (except dark_mode)
    try {
      for (final key in _keysToClear) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      developer.log(
        '⚠️ Failed to clear old preference keys: $e',
        name: 'SettingsMigrationService',
      );
    }

    // Mark migration as complete
    try {
      await prefs.setBool(_migrationDoneKey, true);
    } catch (e) {
      developer.log(
        '⚠️ Failed to mark migration as complete: $e',
        name: 'SettingsMigrationService',
      );
    }

    developer.log(
      '✅ Settings migration complete: $count settings migrated',
      name: 'SettingsMigrationService',
    );

    return count;
  }

  /// Get a value from SharedPreferences regardless of type.
  static dynamic _getPrefsValue(SharedPreferences prefs, String key) {
    // Special handling for runtime_playback_config_v1 (stored as JSON string)
    if (key == 'runtime_playback_config_v1') {
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr);
          // Validate that it's a Map (expected structure)
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          developer.log(
            '  ⚠️ runtime_playback_config_v1 is not a valid JSON object, skipping',
            name: 'SettingsMigrationService',
          );
          return null;
        } catch (e) {
          developer.log(
            '  ⚠️ Failed to parse runtime_playback_config_v1 JSON: $e',
            name: 'SettingsMigrationService',
          );
          return null;
        }
      }
      return null;
    }

    // Try different types
    final boolValue = prefs.getBool(key);
    if (boolValue != null) return boolValue;

    final doubleValue = prefs.getDouble(key);
    if (doubleValue != null) return doubleValue;

    final intValue = prefs.getInt(key);
    if (intValue != null) return intValue;

    final stringValue = prefs.getString(key);
    if (stringValue != null) return stringValue;

    return null;
  }

  /// Map old SharedPreferences keys to SQLite keys.
  static String _mapKey(String spKey) {
    // RuntimePlaybackConfig is stored as a single JSON blob
    if (spKey == 'runtime_playback_config_v1') {
      return SettingsKeys.runtimePlaybackConfig;
    }
    // Other keys map directly (they already use snake_case)
    return spKey;
  }
}
