import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tts_engines/tts_engines.dart';

import '../daos/cache_dao.dart';
import '../daos/settings_dao.dart';
import '../sqlite_cache_metadata_storage.dart';

/// Migrates cache metadata from JSON to SQLite.
///
/// This is a one-time migration that:
/// 1. Reads existing .cache_metadata.json if present
/// 2. Migrates entries and quota settings to SQLite
/// 3. Deletes the JSON file after successful migration
/// 4. Sets a flag to prevent re-running
class CacheMigrationService {
  static const _migrationCompleteKey = 'cache_json_migration_complete';

  /// Check if migration is needed.
  static Future<bool> needsMigration(Database db) async {
    final settingsDao = SettingsDao(db);

    // Check if migration was already completed
    final complete = await settingsDao.getBool(_migrationCompleteKey);
    if (complete == true) return false;

    // Check if JSON file exists
    final jsonFile = await _getJsonMetadataFile();
    return await jsonFile.exists();
  }

  /// Run the migration from JSON to SQLite.
  ///
  /// Returns the number of entries migrated.
  static Future<int> migrate(Database db) async {
    final jsonFile = await _getJsonMetadataFile();
    if (!await jsonFile.exists()) return 0;

    if (kDebugMode) {
      debugPrint('📦 Starting cache metadata migration from JSON to SQLite...');
    }

    try {
      // Create JSON storage to read from
      final jsonStorage = JsonCacheMetadataStorage(jsonFile);

      // Load entries and quota from JSON
      final entries = await jsonStorage.getEntriesForMigration();
      final quota = await jsonStorage.loadQuotaSettings();

      if (entries.isEmpty) {
        if (kDebugMode) debugPrint('📦 No cache entries to migrate');
        await _markComplete(db);
        return 0;
      }

      // Create SQLite storage
      final cacheDao = CacheDao(db);
      final settingsDao = SettingsDao(db);
      final sqliteStorage = SqliteCacheMetadataStorage(cacheDao, settingsDao);

      // Migrate quota settings first
      if (quota != null) {
        await sqliteStorage.saveQuotaSettings(quota);
        if (kDebugMode) {
          debugPrint('📦 Migrated quota settings: ${quota.sizeGB}GB');
        }
      }

      // Migrate entries in batches
      int migrated = 0;
      final batch = <String, CacheEntryMetadata>{};

      for (final entry in entries.entries) {
        batch[entry.key] = entry.value;
        migrated++;

        // Commit in batches of 100
        if (batch.length >= 100) {
          await sqliteStorage.saveEntries(batch);
          batch.clear();
        }
      }

      // Commit remaining entries
      if (batch.isNotEmpty) {
        // Load existing and merge for final batch
        final existing = await sqliteStorage.loadEntries();
        existing.addAll(batch);
        await sqliteStorage.saveEntries(existing);
      }

      // Mark migration complete
      await _markComplete(db);

      // Backup and delete JSON file
      await _backupAndDeleteJson(jsonFile);

      if (kDebugMode) {
        debugPrint('📦 Cache metadata migration complete: $migrated entries');
      }

      return migrated;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Cache metadata migration failed: $e');
      }
      // Don't mark complete - allow retry
      return 0;
    }
  }

  static Future<File> _getJsonMetadataFile() async {
    final cacheDir = await getApplicationCacheDirectory();
    return File('${cacheDir.path}/tts_audio/.cache_metadata.json');
  }

  static Future<void> _markComplete(Database db) async {
    final settingsDao = SettingsDao(db);
    await settingsDao.setBool(_migrationCompleteKey, true);
  }

  static Future<void> _backupAndDeleteJson(File jsonFile) async {
    try {
      // Create backup
      final backupPath = '${jsonFile.path}.migrated';
      await jsonFile.copy(backupPath);

      // Delete original
      await jsonFile.delete();

      if (kDebugMode) {
        debugPrint('📦 JSON file backed up and deleted');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to cleanup JSON file: $e');
      }
    }
  }
}
