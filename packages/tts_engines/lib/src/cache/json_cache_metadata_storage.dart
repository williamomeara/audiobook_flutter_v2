import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'cache_entry_metadata.dart';
import 'cache_metadata_storage.dart';
import 'intelligent_cache_manager.dart';

/// JSON file-based implementation of CacheMetadataStorage.
///
/// This is the legacy storage method, kept for:
/// - Migration from old versions
/// - Fallback if SQLite is unavailable
class JsonCacheMetadataStorage implements CacheMetadataStorage {
  JsonCacheMetadataStorage(this._file);

  final File _file;

  // In-memory cache for fast access
  Map<String, CacheEntryMetadata>? _entriesCache;
  CacheQuotaSettings? _quotaCache;

  @override
  Future<Map<String, CacheEntryMetadata>> loadEntries() async {
    if (_entriesCache != null) return Map.from(_entriesCache!);

    try {
      if (await _file.exists()) {
        final content = await _file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        _entriesCache = {};
        if (json['entries'] != null) {
          final entries = json['entries'] as Map<String, dynamic>;
          for (final e in entries.entries) {
            _entriesCache![e.key] = CacheEntryMetadata.fromJson(
              e.value as Map<String, dynamic>,
            );
          }
        }

        if (json['quota'] != null) {
          _quotaCache = CacheQuotaSettings.fromJson(
            json['quota'] as Map<String, dynamic>,
          );
        }

        developer.log(
          '📦 JSON: Loaded ${_entriesCache!.length} cache entries',
          name: 'JsonCacheMetadataStorage',
        );
      }
    } catch (e) {
      developer.log(
        '⚠️ Failed to load JSON cache metadata: $e',
        name: 'JsonCacheMetadataStorage',
      );
    }

    return _entriesCache ?? {};
  }

  @override
  Future<void> saveEntries(Map<String, CacheEntryMetadata> entries) async {
    _entriesCache = Map.from(entries);
    await _save();
  }

  @override
  Future<CacheQuotaSettings?> loadQuotaSettings() async {
    if (_quotaCache != null) return _quotaCache;

    // Force load from file
    await loadEntries();
    return _quotaCache;
  }

  @override
  Future<void> saveQuotaSettings(CacheQuotaSettings settings) async {
    _quotaCache = settings;
    await _save();
  }

  @override
  Future<void> upsertEntry(CacheEntryMetadata entry) async {
    _entriesCache ??= await loadEntries();
    _entriesCache![entry.key] = entry;
    await _save();
  }

  @override
  Future<void> removeEntry(String key) async {
    _entriesCache ??= await loadEntries();
    _entriesCache!.remove(key);
    await _save();
  }

  @override
  Future<void> removeEntries(List<String> keys) async {
    _entriesCache ??= await loadEntries();
    for (final key in keys) {
      _entriesCache!.remove(key);
    }
    await _save();
  }

  @override
  Future<int> getTotalSizeFromMetadata() async {
    _entriesCache ??= await loadEntries();
    return _entriesCache!.values.fold<int>(0, (sum, e) => sum + e.sizeBytes);
  }

  @override
  Future<Map<String, int>> getSizeByBook() async {
    _entriesCache ??= await loadEntries();
    final result = <String, int>{};
    for (final entry in _entriesCache!.values) {
      result[entry.bookId] = (result[entry.bookId] ?? 0) + entry.sizeBytes;
    }
    return result;
  }

  @override
  Future<Map<String, int>> getSizeByVoice() async {
    _entriesCache ??= await loadEntries();
    final result = <String, int>{};
    for (final entry in _entriesCache!.values) {
      result[entry.voiceId] = (result[entry.voiceId] ?? 0) + entry.sizeBytes;
    }
    return result;
  }

  @override
  Future<int> getCompressedCount() async {
    _entriesCache ??= await loadEntries();
    return _entriesCache!.values.where((e) => e.compressionState == CompressionState.m4a).length;
  }

  @override
  Future<List<CacheEntryMetadata>> getUncompressedEntries() async {
    _entriesCache ??= await loadEntries();
    return _entriesCache!.values
        .where((e) => e.compressionState == CompressionState.wav)
        .toList();
  }

  @override
  Future<void> updateCompressionState(
    String key,
    CompressionState state, {
    DateTime? compressionStartedAt,
  }) async {
    _entriesCache ??= await loadEntries();
    final entry = _entriesCache![key];
    if (entry != null) {
      _entriesCache![key] = entry.copyWith(
        compressionState: state,
        compressionStartedAt: compressionStartedAt,
      );
      await _save();
    }
  }

  @override
  Future<void> replaceEntry({
    required String oldKey,
    required CacheEntryMetadata newEntry,
  }) async {
    _entriesCache ??= await loadEntries();
    _entriesCache!.remove(oldKey);
    _entriesCache![newEntry.key] = newEntry;
    await _save();
  }

  Future<void> _save() async {
    try {
      final json = {
        if (_quotaCache != null) 'quota': _quotaCache!.toJson(),
        'entries': {
          for (final e in (_entriesCache ?? {}).entries) e.key: e.value.toJson(),
        },
      };
      await _file.writeAsString(jsonEncode(json));
    } catch (e) {
      developer.log(
        '⚠️ Failed to save JSON cache metadata: $e',
        name: 'JsonCacheMetadataStorage',
      );
    }
  }

  /// Check if the JSON file exists (for migration detection).
  Future<bool> exists() => _file.exists();

  /// Delete the JSON file after migration.
  Future<void> delete() async {
    if (await _file.exists()) {
      await _file.delete();
    }
    _entriesCache = null;
    _quotaCache = null;
  }

  /// Get raw entries for migration purposes.
  Future<Map<String, CacheEntryMetadata>> getEntriesForMigration() async {
    return await loadEntries();
  }
}
