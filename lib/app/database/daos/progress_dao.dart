import 'package:sqflite/sqflite.dart';

/// Data Access Object for reading_progress table.
///
/// Tracks the current reading position for each book.
/// Position is stored as (chapter_index, segment_index).
class ProgressDao {
  final Database _db;

  ProgressDao(this._db);

  /// Get progress for a book.
  Future<Map<String, dynamic>?> getProgress(String bookId) async {
    final results = await _db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Update reading position.
  Future<void> updatePosition(
      String bookId, int chapterIndex, int segmentIndex) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'reading_progress',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'segment_index': segmentIndex,
        'last_played_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Add listening time to a book.
  Future<void> addListenTime(String bookId, int durationMs) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // First try to update existing record
    final updated = await _db.rawUpdate('''
      UPDATE reading_progress
      SET total_listen_time_ms = total_listen_time_ms + ?,
          last_played_at = ?,
          updated_at = ?
      WHERE book_id = ?
    ''', [durationMs, now, now, bookId]);

    // If no record exists, create one
    if (updated == 0) {
      await _db.insert('reading_progress', {
        'book_id': bookId,
        'chapter_index': 0,
        'segment_index': 0,
        'last_played_at': now,
        'total_listen_time_ms': durationMs,
        'updated_at': now,
      });
    }
  }

  /// Get total listen time for a book.
  Future<int> getTotalListenTime(String bookId) async {
    final result = await _db.rawQuery('''
      SELECT total_listen_time_ms FROM reading_progress
      WHERE book_id = ?
    ''', [bookId]);
    if (result.isEmpty) return 0;
    return result.first['total_listen_time_ms'] as int? ?? 0;
  }

  /// Get last played timestamp for a book.
  /// Returns milliseconds since epoch, or null if never played.
  Future<int?> getLastPlayedAt(String bookId) async {
    final result = await _db.rawQuery('''
      SELECT last_played_at FROM reading_progress
      WHERE book_id = ?
    ''', [bookId]);
    if (result.isEmpty) return null;
    return result.first['last_played_at'] as int?;
  }

  /// Get all books with progress, ordered by last played.
  Future<List<Map<String, dynamic>>> getRecentlyPlayed({int limit = 10}) async {
    return await _db.rawQuery('''
      SELECT b.*, rp.chapter_index, rp.segment_index,
             rp.last_played_at, rp.total_listen_time_ms
      FROM books b
      INNER JOIN reading_progress rp ON b.id = rp.book_id
      WHERE rp.last_played_at IS NOT NULL
      ORDER BY rp.last_played_at DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Delete progress for a book.
  Future<void> deleteProgress(String bookId) async {
    await _db.delete(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// Reset progress to beginning.
  Future<void> resetProgress(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'reading_progress',
      {
        'chapter_index': 0,
        'segment_index': 0,
        'updated_at': now,
      },
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
}
