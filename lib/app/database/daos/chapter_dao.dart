import 'package:sqflite/sqflite.dart';

/// Data Access Object for chapters table.
///
/// Handles chapter metadata operations.
/// Note: Chapters store metadata only - text content is in segments table.
class ChapterDao {
  final Database _db;

  ChapterDao(this._db);

  /// Get all chapters for a book, ordered by chapter index.
  Future<List<Map<String, dynamic>>> getChaptersForBook(String bookId) async {
    return await _db.query(
      'chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC',
    );
  }

  /// Get a single chapter by book ID and chapter index.
  Future<Map<String, dynamic>?> getChapter(
      String bookId, int chapterIndex) async {
    final results = await _db.query(
      'chapters',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Insert a single chapter.
  Future<void> insertChapter(Map<String, dynamic> chapter) async {
    await _db.insert('chapters', chapter);
  }

  /// Batch insert chapters for a book (used during import).
  Future<void> insertChapters(List<Map<String, dynamic>> chapters) async {
    final batch = _db.batch();
    for (final chapter in chapters) {
      batch.insert('chapters', chapter);
    }
    await batch.commit(noResult: true);
  }

  /// Get segment count for a specific chapter.
  Future<int> getSegmentCount(String bookId, int chapterIndex) async {
    final result = await _db.rawQuery('''
      SELECT segment_count FROM chapters
      WHERE book_id = ? AND chapter_index = ?
    ''', [bookId, chapterIndex]);
    if (result.isEmpty) return 0;
    return result.first['segment_count'] as int? ?? 0;
  }

  /// Get total chapter count for a book.
  Future<int> getChapterCount(String bookId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM chapters WHERE book_id = ?',
      [bookId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total estimated duration for a book (sum of all chapters).
  Future<int> getTotalDurationMs(String bookId) async {
    final result = await _db.rawQuery('''
      SELECT SUM(estimated_duration_ms) as total FROM chapters
      WHERE book_id = ?
    ''', [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete all chapters for a book.
  Future<void> deleteChaptersForBook(String bookId) async {
    await _db.delete(
      'chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
}
