import 'package:sqflite/sqflite.dart';

/// Data Access Object for segments table.
///
/// Segments contain the actual text content, pre-segmented at import time.
/// This is the source of truth for text during playback - no runtime segmentation.
class SegmentDao {
  final Database _db;

  SegmentDao(this._db);

  /// Get all segments for a chapter, ordered by segment index.
  /// 
  /// If [minConfidence] is provided, only segments with confidence >= minConfidence
  /// are returned. Segments with null confidence are always included.
  Future<List<Map<String, dynamic>>> getSegmentsForChapter(
      String bookId, int chapterIndex, {double? minConfidence}) async {
    if (minConfidence == null || minConfidence <= 0) {
      return await _db.query(
        'segments',
        where: 'book_id = ? AND chapter_index = ?',
        whereArgs: [bookId, chapterIndex],
        orderBy: 'segment_index ASC',
      );
    }
    // Filter by confidence, but include segments with null confidence
    return await _db.query(
      'segments',
      where: 'book_id = ? AND chapter_index = ? AND (content_confidence IS NULL OR content_confidence >= ?)',
      whereArgs: [bookId, chapterIndex, minConfidence],
      orderBy: 'segment_index ASC',
    );
  }

  /// Get a single segment by coordinates.
  Future<Map<String, dynamic>?> getSegment(
      String bookId, int chapterIndex, int segmentIndex) async {
    final results = await _db.query(
      'segments',
      where: 'book_id = ? AND chapter_index = ? AND segment_index = ?',
      whereArgs: [bookId, chapterIndex, segmentIndex],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Get only the text for a segment (optimized for TTS synthesis).
  Future<String?> getSegmentText(
      String bookId, int chapterIndex, int segmentIndex) async {
    final results = await _db.rawQuery('''
      SELECT text FROM segments
      WHERE book_id = ? AND chapter_index = ? AND segment_index = ?
    ''', [bookId, chapterIndex, segmentIndex]);
    if (results.isEmpty) return null;
    return results.first['text'] as String?;
  }

  /// Insert a single segment.
  Future<void> insertSegment(Map<String, dynamic> segment) async {
    await _db.insert('segments', segment);
  }

  /// Batch insert segments for a chapter (used during import).
  Future<void> insertSegments(List<Map<String, dynamic>> segments) async {
    final batch = _db.batch();
    for (final segment in segments) {
      batch.insert('segments', segment);
    }
    await batch.commit(noResult: true);
  }

  /// Get segment count for a chapter.
  Future<int> getSegmentCount(String bookId, int chapterIndex) async {
    final result = await _db.rawQuery('''
      SELECT COUNT(*) as count FROM segments
      WHERE book_id = ? AND chapter_index = ?
    ''', [bookId, chapterIndex]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total segment count for a book.
  Future<int> getTotalSegmentCount(String bookId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM segments WHERE book_id = ?',
      [bookId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get all segment texts for a chapter (for full chapter text reconstruction).
  Future<List<String>> getChapterTexts(String bookId, int chapterIndex) async {
    final results = await _db.rawQuery('''
      SELECT text FROM segments
      WHERE book_id = ? AND chapter_index = ?
      ORDER BY segment_index ASC
    ''', [bookId, chapterIndex]);
    return results.map((r) => r['text'] as String).toList();
  }

  /// Delete all segments for a book.
  Future<void> deleteSegmentsForBook(String bookId) async {
    await _db.delete(
      'segments',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// Delete all segments for a chapter.
  Future<void> deleteSegmentsForChapter(String bookId, int chapterIndex) async {
    await _db.delete(
      'segments',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
    );
  }
}
