import 'cache_entry_metadata.dart';
import 'intelligent_cache_manager.dart';

/// Abstract interface for cache metadata storage.
///
/// This allows IntelligentCacheManager to work with different backends:
/// - JSON file (legacy/fallback)
/// - SQLite (preferred)
///
/// The app layer provides the implementation.
abstract class CacheMetadataStorage {
  /// Load all cache entry metadata.
  Future<Map<String, CacheEntryMetadata>> loadEntries();

  /// Save all cache entry metadata.
  Future<void> saveEntries(Map<String, CacheEntryMetadata> entries);

  /// Load quota settings.
  Future<CacheQuotaSettings?> loadQuotaSettings();

  /// Save quota settings.
  Future<void> saveQuotaSettings(CacheQuotaSettings settings);

  /// Add or update a single entry (for incremental saves).
  Future<void> upsertEntry(CacheEntryMetadata entry);

  /// Remove a single entry.
  Future<void> removeEntry(String key);

  /// Remove multiple entries.
  Future<void> removeEntries(List<String> keys);

  /// Get total size from stored metadata (faster than filesystem scan).
  Future<int> getTotalSizeFromMetadata();

  /// Get usage stats grouped by book.
  Future<Map<String, int>> getSizeByBook();

  /// Get usage stats grouped by voice.
  Future<Map<String, int>> getSizeByVoice();

  /// Get count of compressed entries.
  Future<int> getCompressedCount();

  /// Get all uncompressed (WAV) entries from database.
  /// 
  /// Queries the database for entries with compressionState = WAV.
  /// Used by compression services to find files needing compression.
  Future<List<CacheEntryMetadata>> getUncompressedEntries();

  /// Update compression state of an entry.
  /// 
  /// Used to mark entry as COMPRESSING before compression starts,
  /// then M4A or FAILED when compression completes.
  /// Atomically updates database.
  Future<void> updateCompressionState(
    String key,
    CompressionState state, {
    DateTime? compressionStartedAt,
  });

  /// Replace an entry atomically.
  /// 
  /// Deletes old entry and inserts new one in a transaction.
  /// Used when converting WAV entry to M4A after compression.
  /// 
  /// Example:
  ///   replaceEntry(
  ///     oldKey: 'segment_001.wav',
  ///     newEntry: metadataForSegment001M4a,
  ///   )
  Future<void> replaceEntry({
    required String oldKey,
    required CacheEntryMetadata newEntry,
  });
}
