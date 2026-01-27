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
  /// Generic method - prefer type-specific methods (getBool, getInt, etc.)
  /// for better type safety and error handling.
  Future<T?> getSetting<T>(String key) async {
    final results = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;

    try {
      final jsonValue = results.first['value'] as String?;
      if (jsonValue == null) return null;

      final decoded = jsonDecode(jsonValue);

      // Safe type checking - only return if it's actually the right type
      // For safety, don't use unsafe 'as' casts that can throw
      if (decoded is T) return decoded;

      // Try soft conversions for common cases
      if (decoded is String) {
        // If we got a string but expected something else, try parsing
        final upperDecoded = decoded.toUpperCase();
        if (upperDecoded == 'TRUE') return true as T?;
        if (upperDecoded == 'FALSE') return false as T?;
        if (int.tryParse(decoded) != null) return int.parse(decoded) as T?;
        if (double.tryParse(decoded) != null) return double.parse(decoded) as T?;
      } else if (decoded is int) {
        // If we got an int, try converting to double if needed
        if (T == double) return (decoded.toDouble()) as T;
      } else if (decoded is Map) {
        // Maps are compatible as dynamic
        if (T == dynamic || T == Map<String, dynamic>) {
          return decoded as T?;
        }
      }

      // No conversion possible
      return null;
    } catch (e) {
      // Silently fail for corrupted data
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
    try {
      final results = await _db.query('settings');
      final map = <String, dynamic>{};
      for (final row in results) {
        try {
          final key = row['key'] as String?;
          final value = row['value'] as String?;
          if (key != null && value != null) {
            map[key] = jsonDecode(value);
          }
        } catch (e) {
          // Skip corrupted entries
          continue;
        }
      }
      return map;
    } catch (e) {
      // If table doesn't exist or other error, return empty map
      return {};
    }
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
    final results = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;

    try {
      final value = results.first['value'] as String;
      final decoded = jsonDecode(value);
      if (decoded is int) return decoded;
      if (decoded is String) return int.tryParse(decoded);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Set an int setting.
  Future<void> setInt(String key, int value) async {
    await setSetting(key, value);
  }

  /// Get a string setting.
  Future<String?> getString(String key) async {
    final results = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;

    try {
      final value = results.first['value'] as String;
      final decoded = jsonDecode(value);
      if (decoded is String) return decoded;
      // If it's another type, convert to string
      return decoded.toString();
    } catch (e) {
      return null;
    }
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

  /// Get a double setting.
  /// Handles both native double and int values.
  Future<double?> getDouble(String key) async {
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
      if (decoded is double) return decoded;
      if (decoded is int) return decoded.toDouble();
      if (decoded is String) {
        return double.tryParse(decoded);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Set a double setting.
  Future<void> setDouble(String key, double value) async {
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
  static const String contentQualityLevel = 'content_quality_level';
}
