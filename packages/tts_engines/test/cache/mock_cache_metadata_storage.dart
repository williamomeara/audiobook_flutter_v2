import 'package:tts_engines/src/cache/cache_metadata_storage.dart';
import 'package:tts_engines/src/cache/cache_entry_metadata.dart';
import 'package:tts_engines/src/cache/intelligent_cache_manager.dart';

/// In-memory mock implementation of CacheMetadataStorage for testing.
///
/// This replaces the legacy JsonCacheMetadataStorage for unit tests,
/// providing a simple in-memory cache without file I/O.
class MockCacheMetadataStorage implements CacheMetadataStorage {
  MockCacheMetadataStorage();

  final Map<String, CacheEntryMetadata> _entries = {};
  CacheQuotaSettings? _quota;

  @override
  Future<Map<String, CacheEntryMetadata>> loadEntries() async {
    return Map.from(_entries);
  }

  @override
  Future<void> saveEntries(Map<String, CacheEntryMetadata> entries) async {
    _entries.clear();
    _entries.addAll(entries);
  }

  @override
  Future<CacheQuotaSettings?> loadQuotaSettings() async {
    return _quota;
  }

  @override
  Future<void> saveQuotaSettings(CacheQuotaSettings settings) async {
    _quota = settings;
  }

  @override
  Future<void> upsertEntry(CacheEntryMetadata entry) async {
    _entries[entry.key] = entry;
  }

  @override
  Future<void> removeEntry(String key) async {
    _entries.remove(key);
  }

  @override
  Future<void> removeEntries(List<String> keys) async {
    for (final key in keys) {
      _entries.remove(key);
    }
  }

  @override
  Future<int> getTotalSizeFromMetadata() async {
    return _entries.values.fold<int>(0, (sum, e) => sum + e.sizeBytes);
  }

  @override
  Future<Map<String, int>> getSizeByBook() async {
    final result = <String, int>{};
    for (final entry in _entries.values) {
      result[entry.bookId] = (result[entry.bookId] ?? 0) + entry.sizeBytes;
    }
    return result;
  }

  @override
  Future<Map<String, int>> getSizeByVoice() async {
    final result = <String, int>{};
    for (final entry in _entries.values) {
      result[entry.voiceId] = (result[entry.voiceId] ?? 0) + entry.sizeBytes;
    }
    return result;
  }

  @override
  Future<int> getCompressedCount() async {
    return _entries.values
        .where((e) => e.compressionState == CompressionState.m4a)
        .length;
  }

  @override
  Future<List<CacheEntryMetadata>> getUncompressedEntries() async {
    return _entries.values
        .where((e) => e.compressionState == CompressionState.wav)
        .toList();
  }

  @override
  Future<void> updateCompressionState(
    String key,
    CompressionState state, {
    DateTime? compressionStartedAt,
  }) async {
    final entry = _entries[key];
    if (entry != null) {
      _entries[key] = entry.copyWith(
        compressionState: state,
        compressionStartedAt: compressionStartedAt,
      );
    }
  }

  @override
  Future<void> replaceEntry({
    required String oldKey,
    required CacheEntryMetadata newEntry,
  }) async {
    _entries.remove(oldKey);
    _entries[newEntry.key] = newEntry;
  }
}
