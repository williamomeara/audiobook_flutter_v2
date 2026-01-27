import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Data Access Object for settings table.
///
/// Provides a key-value store for app configuration.
/// Values are JSON-encoded for flexibility.
///
/// Note: dark_mode stays in SharedPreferences for instant startup.
/// All other settings are stored here.
class SettingsDao {
  final Database _db;

  SettingsDao(this._db);

  /// Get a setting value by key.
  Future<T?> getSetting<T>(String key) async {
    final results = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final value = results.first['value'] as String;
    try {
      final decoded = jsonDecode(value);
      return decoded as T?;
    } catch (e) {
      // If decoding fails, return null
      return null;
    }
  }

  /// Get a setting with a default value if not found.
  Future<T> getSettingOr<T>(String key, T defaultValue) async {
    final value = await getSetting<T>(key);
    return value ?? defaultValue;
  }

  /// Set a setting value.
  Future<void> setSetting(String key, dynamic value) async {
    await _db.insert(
      'settings',
      {
        'key': key,
        'value': jsonEncode(value),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a setting.
  Future<void> deleteSetting(String key) async {
    await _db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  /// Get all settings as a map.
  Future<Map<String, dynamic>> getAllSettings() async {
    final results = await _db.query('settings');
    final map = <String, dynamic>{};
    for (final row in results) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      map[key] = jsonDecode(value);
    }
    return map;
  }

  /// Check if a setting exists.
  Future<bool> hasSetting(String key) async {
    final result = await _db.rawQuery(
      'SELECT 1 FROM settings WHERE key = ? LIMIT 1',
      [key],
    );
    return result.isNotEmpty;
  }

  /// Get an int setting.
  Future<int?> getInt(String key) async {
    return await getSetting<int>(key);
  }

  /// Set an int setting.
  Future<void> setInt(String key, int value) async {
    await setSetting(key, value);
  }

  /// Get a string setting.
  Future<String?> getString(String key) async {
    return await getSetting<String>(key);
  }

  /// Set a string setting.
  Future<void> setString(String key, String value) async {
    await setSetting(key, value);
  }

  /// Get a bool setting.
  /// Handles both native bool and string representations.
  Future<bool?> getBool(String key) async {
    final results = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;

    final value = results.first['value'] as String;
    try {
      final decoded = jsonDecode(value);
      if (decoded is bool) return decoded;
      if (decoded is String) {
        // Handle string representations like "true", "false"
        return decoded.toLowerCase() == 'true';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Set a bool setting.
  Future<void> setBool(String key, bool value) async {
    await setSetting(key, value);
  }

  /// Batch set multiple settings.
  Future<void> setSettings(Map<String, dynamic> settings) async {
    final batch = _db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in settings.entries) {
      batch.insert(
        'settings',
        {
          'key': entry.key,
          'value': jsonEncode(entry.value),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}

/// Known settings keys as constants.
class SettingsKeys {
  static const String darkMode = 'dark_mode';
  static const String selectedVoice = 'selected_voice';
  static const String autoAdvanceChapters = 'auto_advance_chapters';
  static const String defaultPlaybackRate = 'default_playback_rate';
  static const String smartSynthesisEnabled = 'smart_synthesis_enabled';
  static const String cacheQuotaGb = 'cache_quota_gb';
  static const String hapticFeedbackEnabled = 'haptic_feedback_enabled';
  static const String synthesisMode = 'synthesis_mode';
  static const String compressOnSynthesize = 'compress_on_synthesize';
  static const String showBufferIndicator = 'show_buffer_indicator';
  static const String showBookCoverBackground = 'show_book_cover_background';
  static const String runtimePlaybackConfig = 'runtime_playback_config';
}
