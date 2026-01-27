import 'dart:developer' as developer;

import 'package:tts_engines/tts_engines.dart';

import 'daos/cache_dao.dart';
import 'daos/settings_dao.dart';

/// SQLite implementation of CacheMetadataStorage.
///
/// Uses CacheDao for database operations and provides the interface
/// expected by IntelligentCacheManager.
class SqliteCacheMetadataStorage implements CacheMetadataStorage {
  SqliteCacheMetadataStorage(this._cacheDao, this._settingsDao);

  final CacheDao _cacheDao;
  final SettingsDao _settingsDao;

  // Settings keys for quota
  static const _quotaMaxSizeKey = 'cache_quota_max_size_bytes';
  static const _quotaWarningThresholdKey = 'cache_quota_warning_percent';
  static const _quotaCompressionThresholdKey = 'cache_quota_compression_percent';

  @override
  Future<Map<String, CacheEntryMetadata>> loadEntries() async {
    try {
      final rows = await _cacheDao.getAllEntriesByFilePath();
      final entries = <String, CacheEntryMetadata>{};

      for (final entry in rows.entries) {
        entries[entry.key] = _rowToMetadata(entry.value);
      }

      developer.log(
        '📦 SQLite: Loaded ${entries.length} cache entries',
        name: 'SqliteCacheMetadataStorage',
      );

      return entries;
    } catch (e) {
      developer.log(
        '⚠️ Failed to load cache entries from SQLite: $e',
        name: 'SqliteCacheMetadataStorage',
      );
      return {};
    }
  }

  @override
  Future<void> saveEntries(Map<String, CacheEntryMetadata> entries) async {
    try {
      // Clear and re-insert all entries
      await _cacheDao.clearAll();

      for (final entry in entries.values) {
        await _cacheDao.upsertEntryByFilePath(_metadataToRow(entry));
      }

      developer.log(
        '📦 SQLite: Saved ${entries.length} cache entries',
        name: 'SqliteCacheMetadataStorage',
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to save cache entries to SQLite: $e',
        name: 'SqliteCacheMetadataStorage',
      );
    }
  }

  @override
  Future<CacheQuotaSettings?> loadQuotaSettings() async {
    try {
      final maxSize = await _settingsDao.getInt(_quotaMaxSizeKey);
      if (maxSize == null) return null;

      final warningThreshold =
          await _settingsDao.getInt(_quotaWarningThresholdKey) ?? 90;
      final compressionThreshold =
          await _settingsDao.getInt(_quotaCompressionThresholdKey) ?? 80;

      return CacheQuotaSettings(
        maxSizeBytes: maxSize,
        warningThresholdPercent: warningThreshold,
        compressionThresholdPercent: compressionThreshold,
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to load quota settings: $e',
        name: 'SqliteCacheMetadataStorage',
      );
      return null;
    }
  }

  @override
  Future<void> saveQuotaSettings(CacheQuotaSettings settings) async {
    try {
      await _settingsDao.setInt(_quotaMaxSizeKey, settings.maxSizeBytes);
      await _settingsDao.setInt(
          _quotaWarningThresholdKey, settings.warningThresholdPercent);
      await _settingsDao.setInt(
          _quotaCompressionThresholdKey, settings.compressionThresholdPercent);
    } catch (e) {
      developer.log(
        '⚠️ Failed to save quota settings: $e',
        name: 'SqliteCacheMetadataStorage',
      );
    }
  }

  @override
  Future<void> upsertEntry(CacheEntryMetadata entry) async {
    try {
      await _cacheDao.upsertEntryByFilePath(_metadataToRow(entry));
    } catch (e) {
      developer.log(
        '⚠️ Failed to upsert cache entry: $e',
        name: 'SqliteCacheMetadataStorage',
      );
    }
  }

  @override
  Future<void> removeEntry(String key) async {
    try {
      await _cacheDao.deleteEntryByFilePath(key);
    } catch (e) {
      developer.log(
        '⚠️ Failed to remove cache entry: $e',
        name: 'SqliteCacheMetadataStorage',
      );
    }
  }

  @override
  Future<void> removeEntries(List<String> keys) async {
    try {
      await _cacheDao.deleteEntriesByFilePaths(keys);
    } catch (e) {
      developer.log(
        '⚠️ Failed to remove cache entries: $e',
        name: 'SqliteCacheMetadataStorage',
      );
    }
  }

  @override
  Future<int> getTotalSizeFromMetadata() async {
    try {
      return await _cacheDao.getTotalSizeFromMetadata();
    } catch (e) {
      developer.log(
        '⚠️ Failed to get total size: $e',
        name: 'SqliteCacheMetadataStorage',
      );
      return 0;
    }
  }

  @override
  Future<Map<String, int>> getSizeByBook() async {
    try {
      return await _cacheDao.getSizeByBook();
    } catch (e) {
      developer.log(
        '⚠️ Failed to get size by book: $e',
        name: 'SqliteCacheMetadataStorage',
      );
      return {};
    }
  }

  @override
  Future<Map<String, int>> getSizeByVoice() async {
    try {
      return await _cacheDao.getSizeByVoice();
    } catch (e) {
      developer.log(
        '⚠️ Failed to get size by voice: $e',
        name: 'SqliteCacheMetadataStorage',
      );
      return {};
    }
  }

  @override
  Future<int> getCompressedCount() async {
    try {
      return await _cacheDao.getCompressedCount();
    } catch (e) {
      developer.log(
        '⚠️ Failed to get compressed count: $e',
        name: 'SqliteCacheMetadataStorage',
      );
      return 0;
    }
  }

  // ============= Conversion helpers =============

  CacheEntryMetadata _rowToMetadata(Map<String, dynamic> row) {
    return CacheEntryMetadata(
      key: row['file_path'] as String,
      sizeBytes: row['size_bytes'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      lastAccessed:
          DateTime.fromMillisecondsSinceEpoch(row['last_accessed_at'] as int),
      accessCount: row['access_count'] as int? ?? 1,
      bookId: row['book_id'] as String,
      voiceId: row['voice_id'] as String? ?? 'unknown',
      segmentIndex: row['segment_index'] as int,
      chapterIndex: row['chapter_index'] as int,
      engineType: row['engine_type'] as String? ?? 'unknown',
      audioDurationMs: row['duration_ms'] as int? ?? 0,
    );
  }

  Map<String, dynamic> _metadataToRow(CacheEntryMetadata entry) {
    return {
      'file_path': entry.key,
      'book_id': entry.bookId,
      'chapter_index': entry.chapterIndex,
      'segment_index': entry.segmentIndex,
      'size_bytes': entry.sizeBytes,
      'duration_ms': entry.audioDurationMs,
      'is_compressed': entry.key.endsWith('.m4a') ? 1 : 0,
      'is_pinned': 0,
      'created_at': entry.createdAt.millisecondsSinceEpoch,
      'last_accessed_at': entry.lastAccessed.millisecondsSinceEpoch,
      'access_count': entry.accessCount,
      'engine_type': entry.engineType,
      'voice_id': entry.voiceId,
    };
  }
}
