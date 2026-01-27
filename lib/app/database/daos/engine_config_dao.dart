import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Data Access Object for engine_configs table.
///
/// Stores TTS engine configuration and calibration data.
/// Used for learned concurrency limits and performance tuning.
class EngineConfigDao {
  final Database _db;

  EngineConfigDao(this._db);

  /// Get config for an engine.
  Future<Map<String, dynamic>?> getConfig(String engineId) async {
    final results = await _db.query(
      'engine_configs',
      where: 'engine_id = ?',
      whereArgs: [engineId],
      limit: 1,
    );
    if (results.isEmpty) return null;

    // Parse config_json if present
    final row = Map<String, dynamic>.from(results.first);
    if (row['config_json'] != null) {
      row['config'] = jsonDecode(row['config_json'] as String);
    }
    return row;
  }

  /// Save config for an engine.
  Future<void> saveConfig(Map<String, dynamic> config) async {
    final row = Map<String, dynamic>.from(config);

    // Serialize config object if present
    if (row.containsKey('config')) {
      row['config_json'] = jsonEncode(row['config']);
      row.remove('config');
    }

    await _db.insert(
      'engine_configs',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update specific fields for an engine.
  Future<void> updateConfig(String engineId, Map<String, dynamic> updates) async {
    // Handle config object serialization
    if (updates.containsKey('config')) {
      updates['config_json'] = jsonEncode(updates['config']);
      updates.remove('config');
    }

    await _db.update(
      'engine_configs',
      updates,
      where: 'engine_id = ?',
      whereArgs: [engineId],
    );
  }

  /// Get last calibration time for an engine.
  Future<DateTime?> getLastCalibrated(String engineId) async {
    final result = await _db.rawQuery('''
      SELECT last_calibrated_at FROM engine_configs
      WHERE engine_id = ?
    ''', [engineId]);
    if (result.isEmpty) return null;
    final timestamp = result.first['last_calibrated_at'] as int?;
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Update last calibration time.
  Future<void> setLastCalibrated(String engineId, DateTime time) async {
    await _db.rawUpdate('''
      UPDATE engine_configs
      SET last_calibrated_at = ?
      WHERE engine_id = ?
    ''', [time.millisecondsSinceEpoch, engineId]);
  }

  /// Get max concurrency for an engine.
  Future<int> getMaxConcurrency(String engineId) async {
    final result = await _db.rawQuery('''
      SELECT max_concurrency FROM engine_configs
      WHERE engine_id = ?
    ''', [engineId]);
    if (result.isEmpty) return 1;
    return result.first['max_concurrency'] as int? ?? 1;
  }

  /// Update max concurrency for an engine.
  Future<void> setMaxConcurrency(String engineId, int maxConcurrency) async {
    // Upsert pattern
    await _db.insert(
      'engine_configs',
      {
        'engine_id': engineId,
        'max_concurrency': maxConcurrency,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all engine configs.
  Future<List<Map<String, dynamic>>> getAllConfigs() async {
    final results = await _db.query('engine_configs');
    return results.map((row) {
      final map = Map<String, dynamic>.from(row);
      if (map['config_json'] != null) {
        map['config'] = jsonDecode(map['config_json'] as String);
      }
      return map;
    }).toList();
  }

  /// Delete config for an engine.
  Future<void> deleteConfig(String engineId) async {
    await _db.delete(
      'engine_configs',
      where: 'engine_id = ?',
      whereArgs: [engineId],
    );
  }
}
