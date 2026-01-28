import 'package:sqflite/sqflite.dart';

/// Data Access Object for completed_chapters table.
///
/// Tracks which chapters have been marked as complete.
class CompletedChaptersDao {
  final Database _db;

  CompletedChaptersDao(this._db);

  /// Get all completed chapter indices for a book.
  Future<Set<int>> getCompletedChapters(String bookId) async {
    final results = await _db.query(
      'completed_chapters',
      columns: ['chapter_index'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    return results.map((r) => r['chapter_index'] as int).toSet();
  }

  /// Check if a specific chapter is completed.
  Future<bool> isChapterCompleted(String bookId, int chapterIndex) async {
    final result = await _db.rawQuery('''
      SELECT 1 FROM completed_chapters
      WHERE book_id = ? AND chapter_index = ?
      LIMIT 1
    ''', [bookId, chapterIndex]);
    return result.isNotEmpty;
  }

  /// Mark a chapter as completed.
  Future<void> markChapterComplete(String bookId, int chapterIndex) async {
    await _db.insert(
      'completed_chapters',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Mark a chapter as incomplete (remove from completed).
  Future<void> markChapterIncomplete(String bookId, int chapterIndex) async {
    await _db.delete(
      'completed_chapters',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
    );
  }

  /// Toggle chapter completion status.
  Future<bool> toggleChapterComplete(String bookId, int chapterIndex) async {
    final isCompleted = await isChapterCompleted(bookId, chapterIndex);
    if (isCompleted) {
      await markChapterIncomplete(bookId, chapterIndex);
      return false;
    } else {
      await markChapterComplete(bookId, chapterIndex);
      return true;
    }
  }

  /// Get completed chapter count for a book.
  Future<int> getCompletedCount(String bookId) async {
    final result = await _db.rawQuery('''
      SELECT COUNT(*) as count FROM completed_chapters
      WHERE book_id = ?
    ''', [bookId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Mark all chapters as complete up to a given index.
  Future<void> markChaptersCompleteUpTo(
      String bookId, int chapterIndex) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = _db.batch();
    for (var i = 0; i <= chapterIndex; i++) {
      batch.insert(
        'completed_chapters',
        {
          'book_id': bookId,
          'chapter_index': i,
          'completed_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Clear all completed chapters for a book.
  Future<void> clearCompletedChapters(String bookId) async {
    await _db.delete(
      'completed_chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
}
