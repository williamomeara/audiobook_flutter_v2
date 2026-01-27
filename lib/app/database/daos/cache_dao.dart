import 'package:sqflite/sqflite.dart';

/// Data Access Object for cache_entries table.
///
/// Manages audio cache metadata with book-centric design.
/// Supports both coordinate-based lookups (book_id, chapter_index, segment_index)
/// and filename-based lookups (file_path) for IntelligentCacheManager compatibility.
class CacheDao {
  final Database _db;

  CacheDao(this._db);

  // ============= Filename-based methods (for CacheMetadataStorage) =============

  /// Get all cache entries as a map keyed by file_path.
  Future<Map<String, Map<String, dynamic>>> getAllEntriesByFilePath() async {
    final results = await _db.query('cache_entries');
    final map = <String, Map<String, dynamic>>{};
    for (final row in results) {
      final filePath = row['file_path'] as String;
      map[filePath] = row;
    }
    return map;
  }

  /// Get a cache entry by file path.
  Future<Map<String, dynamic>?> getEntryByFilePath(String filePath) async {
    final results = await _db.query(
      'cache_entries',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Upsert a cache entry by file path.
  Future<void> upsertEntryByFilePath(Map<String, dynamic> entry) async {
    await _db.insert(
      'cache_entries',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a cache entry by file path.
  Future<void> deleteEntryByFilePath(String filePath) async {
    await _db.delete(
      'cache_entries',
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  /// Delete multiple entries by file paths.
  Future<void> deleteEntriesByFilePaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return;
    final placeholders = filePaths.map((_) => '?').join(',');
    await _db.rawDelete(
      'DELETE FROM cache_entries WHERE file_path IN ($placeholders)',
      filePaths,
    );
  }

  /// Get total size from metadata.
  Future<int> getTotalSizeFromMetadata() async {
    final result = await _db.rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) as total FROM cache_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get size grouped by book.
  Future<Map<String, int>> getSizeByBook() async {
    final results = await _db.rawQuery('''
      SELECT book_id, COALESCE(SUM(size_bytes), 0) as total
      FROM cache_entries
      GROUP BY book_id
    ''');
    final map = <String, int>{};
    for (final row in results) {
      map[row['book_id'] as String] = row['total'] as int;
    }
    return map;
  }

  /// Get size grouped by voice.
  Future<Map<String, int>> getSizeByVoice() async {
    final results = await _db.rawQuery('''
      SELECT COALESCE(voice_id, 'unknown') as voice_id,
             COALESCE(SUM(size_bytes), 0) as total
      FROM cache_entries
      GROUP BY voice_id
    ''');
    final map = <String, int>{};
    for (final row in results) {
      map[row['voice_id'] as String] = row['total'] as int;
    }
    return map;
  }

  /// Get count of compressed entries (files ending with .m4a).
  Future<int> getCompressedCount() async {
    final result = await _db.rawQuery('''
      SELECT COUNT(*) as count FROM cache_entries
      WHERE file_path LIKE '%.m4a'
    ''');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all entries (for cache clear operation).
  Future<void> clearAll() async {
    await _db.delete('cache_entries');
  }

  // ============= Coordinate-based methods (original) =============

  /// Get a cache entry by coordinates.
  Future<Map<String, dynamic>?> getEntry(
      String bookId, int chapterIndex, int segmentIndex) async {
    final results = await _db.query(
      'cache_entries',
      where: 'book_id = ? AND chapter_index = ? AND segment_index = ?',
      whereArgs: [bookId, chapterIndex, segmentIndex],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Check if a segment is cached.
  Future<bool> isSegmentCached(
      String bookId, int chapterIndex, int segmentIndex) async {
    final result = await _db.rawQuery('''
      SELECT 1 FROM cache_entries
      WHERE book_id = ? AND chapter_index = ? AND segment_index = ?
      LIMIT 1
    ''', [bookId, chapterIndex, segmentIndex]);
    return result.isNotEmpty;
  }

  /// Get all cache entries for a book.
  Future<List<Map<String, dynamic>>> getEntriesForBook(String bookId) async {
    return await _db.query(
      'cache_entries',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC, segment_index ASC',
    );
  }

  /// Get all cache entries for a chapter.
  Future<List<Map<String, dynamic>>> getEntriesForChapter(
      String bookId, int chapterIndex) async {
    return await _db.query(
      'cache_entries',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      orderBy: 'segment_index ASC',
    );
  }

  /// Count cached segments for a book.
  Future<int> countForBook(String bookId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM cache_entries WHERE book_id = ?',
      [bookId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count cached segments for a chapter.
  Future<int> countForChapter(String bookId, int chapterIndex) async {
    final result = await _db.rawQuery('''
      SELECT COUNT(*) as count FROM cache_entries
      WHERE book_id = ? AND chapter_index = ?
    ''', [bookId, chapterIndex]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total cache size for a book in bytes.
  Future<int> totalSizeForBook(String bookId) async {
    final result = await _db.rawQuery(
      'SELECT SUM(size_bytes) as total FROM cache_entries WHERE book_id = ?',
      [bookId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total cache size in bytes.
  Future<int> totalSize() async {
    final result = await _db.rawQuery(
      'SELECT SUM(size_bytes) as total FROM cache_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Insert a new cache entry.
  Future<void> insertEntry(Map<String, dynamic> entry) async {
    await _db.insert(
      'cache_entries',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update last accessed timestamp.
  Future<void> updateLastAccessed(
      String bookId, int chapterIndex, int segmentIndex) async {
    await _db.rawUpdate('''
      UPDATE cache_entries
      SET last_accessed_at = ?
      WHERE book_id = ? AND chapter_index = ? AND segment_index = ?
    ''', [DateTime.now().millisecondsSinceEpoch, bookId, chapterIndex, segmentIndex]);
  }

  /// Delete a cache entry.
  Future<void> deleteEntry(
      String bookId, int chapterIndex, int segmentIndex) async {
    await _db.delete(
      'cache_entries',
      where: 'book_id = ? AND chapter_index = ? AND segment_index = ?',
      whereArgs: [bookId, chapterIndex, segmentIndex],
    );
  }

  /// Delete all cache entries for a book (used when changing voice).
  Future<void> deleteAllForBook(String bookId) async {
    await _db.delete(
      'cache_entries',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// Get LRU eviction candidates (oldest accessed, unpinned entries).
  Future<List<Map<String, dynamic>>> getLRUCandidates(int limit) async {
    return await _db.query(
      'cache_entries',
      where: 'is_pinned = 0',
      orderBy: 'last_accessed_at ASC',
      limit: limit,
    );
  }

  /// Get cache statistics grouped by book.
  Future<List<Map<String, dynamic>>> getCacheStatsByBook() async {
    return await _db.rawQuery('''
      SELECT book_id,
             COUNT(*) as segment_count,
             SUM(size_bytes) as total_bytes,
             SUM(CASE WHEN is_compressed = 1 THEN 1 ELSE 0 END) as compressed_count
      FROM cache_entries
      GROUP BY book_id
    ''');
  }

  /// Get count of compressed vs uncompressed entries.
  Future<Map<String, int>> getCompressionStats() async {
    final result = await _db.rawQuery('''
      SELECT
        SUM(CASE WHEN is_compressed = 1 THEN 1 ELSE 0 END) as compressed,
        SUM(CASE WHEN is_compressed = 0 THEN 1 ELSE 0 END) as uncompressed
      FROM cache_entries
    ''');
    if (result.isEmpty) {
      return {'compressed': 0, 'uncompressed': 0};
    }
    return {
      'compressed': result.first['compressed'] as int? ?? 0,
      'uncompressed': result.first['uncompressed'] as int? ?? 0,
    };
  }

  /// Mark entries as compressed (batch update after compression).
  Future<void> markCompressed(List<int> entryIds) async {
    if (entryIds.isEmpty) return;
    final placeholders = entryIds.map((_) => '?').join(',');
    await _db.rawUpdate('''
      UPDATE cache_entries
      SET is_compressed = 1
      WHERE id IN ($placeholders)
    ''', entryIds);
  }

  /// Pin/unpin a cache entry.
  Future<void> setPinned(
      String bookId, int chapterIndex, int segmentIndex, bool pinned) async {
    await _db.rawUpdate('''
      UPDATE cache_entries
      SET is_pinned = ?
      WHERE book_id = ? AND chapter_index = ? AND segment_index = ?
    ''', [pinned ? 1 : 0, bookId, chapterIndex, segmentIndex]);
  }
}
