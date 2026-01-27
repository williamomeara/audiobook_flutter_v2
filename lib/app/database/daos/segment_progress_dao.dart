import 'package:sqflite/sqflite.dart';

/// Data Access Object for segment_progress table.
///
/// Tracks which segments have been listened to, enabling:
/// - Chapter completion percentage calculation
/// - Visual indication of listened vs unlistened segments
/// - "Mark Chapter Read/Unread" functionality
class SegmentProgressDao {
  final Database _db;

  SegmentProgressDao(this._db);

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK PROGRESS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mark a segment as listened.
  /// 
  /// If already marked, this is a no-op (INSERT OR IGNORE).
  Future<void> markListened(
    String bookId,
    int chapterIndex,
    int segmentIndex,
  ) async {
    await _db.insert(
      'segment_progress',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'segment_index': segmentIndex,
        'listened_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Mark multiple segments as listened in a batch.
  /// 
  /// More efficient than calling markListened multiple times.
  Future<void> markManyListened(
    String bookId,
    int chapterIndex,
    List<int> segmentIndices,
  ) async {
    if (segmentIndices.isEmpty) return;

    final batch = _db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final segmentIndex in segmentIndices) {
      batch.insert(
        'segment_progress',
        {
          'book_id': bookId,
          'chapter_index': chapterIndex,
          'segment_index': segmentIndex,
          'listened_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Mark all segments in a chapter as listened.
  /// 
  /// Requires segment count to be provided (from chapters table or segments).
  Future<void> markChapterListened(
    String bookId,
    int chapterIndex,
    int segmentCount,
  ) async {
    final segmentIndices = List.generate(segmentCount, (i) => i);
    await markManyListened(bookId, chapterIndex, segmentIndices);
  }

  /// Mark all segments in a chapter as unlistened (clear progress).
  Future<void> clearChapterProgress(String bookId, int chapterIndex) async {
    await _db.delete(
      'segment_progress',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
    );
  }

  /// Clear all progress for a book.
  Future<void> clearBookProgress(String bookId) async {
    await _db.delete(
      'segment_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERY PROGRESS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a specific segment has been listened to.
  Future<bool> isSegmentListened(
    String bookId,
    int chapterIndex,
    int segmentIndex,
  ) async {
    final result = await _db.query(
      'segment_progress',
      where: 'book_id = ? AND chapter_index = ? AND segment_index = ?',
      whereArgs: [bookId, chapterIndex, segmentIndex],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get the set of listened segment indices for a chapter.
  Future<Set<int>> getListenedSegments(
    String bookId,
    int chapterIndex,
  ) async {
    final results = await _db.query(
      'segment_progress',
      columns: ['segment_index'],
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
    );
    return results.map((row) => row['segment_index'] as int).toSet();
  }

  /// Get progress for a single chapter.
  /// 
  /// Returns null if no segments exist for this chapter.
  Future<ChapterProgress?> getChapterProgress(
    String bookId,
    int chapterIndex,
  ) async {
    // Get total segment count from segments table
    final totalResult = await _db.rawQuery('''
      SELECT COUNT(*) as total 
      FROM segments 
      WHERE book_id = ? AND chapter_index = ?
    ''', [bookId, chapterIndex]);

    if (totalResult.isEmpty) return null;
    final total = totalResult.first['total'] as int;
    if (total == 0) return null;

    // Get listened count from segment_progress
    final listenedResult = await _db.rawQuery('''
      SELECT COUNT(*) as listened 
      FROM segment_progress 
      WHERE book_id = ? AND chapter_index = ?
    ''', [bookId, chapterIndex]);

    final listened = listenedResult.first['listened'] as int;

    return ChapterProgress(
      chapterIndex: chapterIndex,
      totalSegments: total,
      listenedSegments: listened,
    );
  }

  /// Get progress for all chapters in a book.
  /// 
  /// Returns a map of chapterIndex -> ChapterProgress.
  /// Only includes chapters that have at least one segment.
  Future<Map<int, ChapterProgress>> getBookProgress(String bookId) async {
    // Join segments with segment_progress to get totals, listened counts, and duration
    final results = await _db.rawQuery('''
      SELECT 
        s.chapter_index,
        COUNT(DISTINCT s.segment_index) as total_segments,
        COUNT(DISTINCT sp.segment_index) as listened_segments,
        COALESCE(SUM(s.estimated_duration_ms), 0) as total_duration_ms
      FROM segments s
      LEFT JOIN segment_progress sp 
        ON s.book_id = sp.book_id 
        AND s.chapter_index = sp.chapter_index 
        AND s.segment_index = sp.segment_index
      WHERE s.book_id = ?
      GROUP BY s.chapter_index
      ORDER BY s.chapter_index
    ''', [bookId]);

    final progressMap = <int, ChapterProgress>{};
    for (final row in results) {
      final chapterIndex = row['chapter_index'] as int;
      progressMap[chapterIndex] = ChapterProgress(
        chapterIndex: chapterIndex,
        totalSegments: row['total_segments'] as int,
        listenedSegments: row['listened_segments'] as int,
        durationMs: row['total_duration_ms'] as int,
      );
    }
    return progressMap;
  }

  /// Get total book progress summary with duration information.
  Future<BookProgressSummary> getBookProgressSummary(String bookId) async {
    final result = await _db.rawQuery('''
      SELECT 
        COUNT(DISTINCT s.segment_index || '-' || s.chapter_index) as total_segments,
        COUNT(DISTINCT sp.segment_index || '-' || sp.chapter_index) as listened_segments,
        COALESCE(SUM(s.estimated_duration_ms), 0) as total_duration_ms,
        COALESCE(SUM(CASE WHEN sp.segment_index IS NOT NULL THEN s.estimated_duration_ms ELSE 0 END), 0) as listened_duration_ms
      FROM segments s
      LEFT JOIN segment_progress sp 
        ON s.book_id = sp.book_id 
        AND s.chapter_index = sp.chapter_index 
        AND s.segment_index = sp.segment_index
      WHERE s.book_id = ?
    ''', [bookId]);

    if (result.isEmpty) {
      return const BookProgressSummary(
        totalSegments: 0,
        listenedSegments: 0,
      );
    }

    return BookProgressSummary(
      totalSegments: result.first['total_segments'] as int,
      listenedSegments: result.first['listened_segments'] as int,
      totalDurationMs: result.first['total_duration_ms'] as int,
      listenedDurationMs: result.first['listened_duration_ms'] as int,
    );
  }

  /// Get the last listened segment in a chapter (for resume).
  /// 
  /// Returns null if no segments have been listened to.
  Future<int?> getLastListenedSegment(
    String bookId,
    int chapterIndex,
  ) async {
    final result = await _db.rawQuery('''
      SELECT segment_index 
      FROM segment_progress 
      WHERE book_id = ? AND chapter_index = ?
      ORDER BY segment_index DESC
      LIMIT 1
    ''', [bookId, chapterIndex]);

    if (result.isEmpty) return null;
    return result.first['segment_index'] as int;
  }
}

/// Progress data for a single chapter.
class ChapterProgress {
  final int chapterIndex;
  final int totalSegments;
  final int listenedSegments;
  final int durationMs;

  const ChapterProgress({
    required this.chapterIndex,
    required this.totalSegments,
    required this.listenedSegments,
    this.durationMs = 0,
  });

  /// Percentage complete (0.0 - 1.0).
  double get percentComplete =>
      totalSegments > 0 ? listenedSegments / totalSegments : 0.0;

  /// Whether the chapter is completely listened to.
  bool get isComplete => listenedSegments >= totalSegments && totalSegments > 0;

  /// Whether any progress has been made.
  bool get hasStarted => listenedSegments > 0;

  /// Chapter duration as Duration.
  Duration get duration => Duration(milliseconds: durationMs);

  @override
  String toString() =>
      'ChapterProgress(ch$chapterIndex: $listenedSegments/$totalSegments = ${(percentComplete * 100).toStringAsFixed(1)}%)';
}

/// Summary of total book progress including duration information.
class BookProgressSummary {
  final int totalSegments;
  final int listenedSegments;
  final int totalDurationMs;
  final int listenedDurationMs;

  const BookProgressSummary({
    required this.totalSegments,
    required this.listenedSegments,
    this.totalDurationMs = 0,
    this.listenedDurationMs = 0,
  });

  /// Percentage complete (0.0 - 1.0).
  double get percentComplete =>
      totalSegments > 0 ? listenedSegments / totalSegments : 0.0;

  /// Whether the book is completely listened to.
  bool get isComplete =>
      listenedSegments >= totalSegments && totalSegments > 0;

  /// Total duration as Duration.
  Duration get totalDuration => Duration(milliseconds: totalDurationMs);

  /// Listened duration as Duration.
  Duration get listenedDuration => Duration(milliseconds: listenedDurationMs);

  /// Remaining duration as Duration.
  Duration get remainingDuration => 
      Duration(milliseconds: (totalDurationMs - listenedDurationMs).clamp(0, totalDurationMs));

  @override
  String toString() =>
      'BookProgressSummary($listenedSegments/$totalSegments = ${(percentComplete * 100).toStringAsFixed(1)}%)';
}
