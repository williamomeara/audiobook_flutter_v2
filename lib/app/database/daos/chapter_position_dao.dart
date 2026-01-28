import 'package:sqflite/sqflite.dart';

/// Data Access Object for chapter_positions table.
///
/// Tracks per-chapter listening positions for resume functionality.
/// Supports both regular chapter positions and a "primary" position
/// for snap-back after browsing other chapters.
class ChapterPositionDao {
  final Database _db;

  ChapterPositionDao(this._db);

  /// Save or update a chapter position.
  ///
  /// [bookId] - The book ID
  /// [chapterIndex] - Which chapter this position is for
  /// [segmentIndex] - The segment position within the chapter
  /// [isPrimary] - Whether this is the main listening position (snap-back target)
  Future<void> savePosition({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
    required bool isPrimary,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'chapter_positions',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'segment_index': segmentIndex,
        'is_primary': isPrimary ? 1 : 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get the primary position for a book (the main listening position).
  ///
  /// Returns null if no primary position exists.
  Future<ChapterPosition?> getPrimaryPosition(String bookId) async {
    final results = await _db.query(
      'chapter_positions',
      where: 'book_id = ? AND is_primary = 1',
      whereArgs: [bookId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return ChapterPosition.fromMap(results.first);
  }

  /// Get position for a specific chapter.
  ///
  /// Returns null if no position exists for this chapter.
  Future<ChapterPosition?> getChapterPosition(
    String bookId,
    int chapterIndex,
  ) async {
    final results = await _db.query(
      'chapter_positions',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return ChapterPosition.fromMap(results.first);
  }

  /// Get all positions for a book, keyed by chapter index.
  Future<Map<int, ChapterPosition>> getAllPositions(String bookId) async {
    final results = await _db.query(
      'chapter_positions',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index',
    );
    return {
      for (final row in results)
        row['chapter_index'] as int: ChapterPosition.fromMap(row)
    };
  }

  /// Clear primary flag from all positions for a book.
  ///
  /// Call this before setting a new primary position to ensure
  /// only one position is marked as primary.
  Future<void> clearPrimaryFlag(String bookId) async {
    await _db.update(
      'chapter_positions',
      {'is_primary': 0},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// Set a specific chapter as the primary position.
  ///
  /// This clears the primary flag from all other chapters for this book
  /// and sets the specified chapter as primary.
  Future<void> setPrimaryChapter(String bookId, int chapterIndex) async {
    await _db.transaction((txn) async {
      // Clear all primary flags for this book
      await txn.update(
        'chapter_positions',
        {'is_primary': 0},
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      
      // Set the specified chapter as primary
      await txn.update(
        'chapter_positions',
        {'is_primary': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'book_id = ? AND chapter_index = ?',
        whereArgs: [bookId, chapterIndex],
      );
    });
  }

  /// Delete all positions for a book.
  ///
  /// Call this when a book is deleted.
  Future<void> deleteBookPositions(String bookId) async {
    await _db.delete(
      'chapter_positions',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// Delete position for a specific chapter.
  Future<void> deleteChapterPosition(String bookId, int chapterIndex) async {
    await _db.delete(
      'chapter_positions',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
    );
  }
}

/// Data class representing a chapter position.
class ChapterPosition {
  /// The chapter index (0-based)
  final int chapterIndex;
  
  /// The segment index within the chapter (0-based)
  final int segmentIndex;
  
  /// Whether this is the primary (main) listening position
  final bool isPrimary;
  
  /// When this position was last updated
  final DateTime updatedAt;

  const ChapterPosition({
    required this.chapterIndex,
    required this.segmentIndex,
    required this.isPrimary,
    required this.updatedAt,
  });

  factory ChapterPosition.fromMap(Map<String, dynamic> map) {
    return ChapterPosition(
      chapterIndex: map['chapter_index'] as int,
      segmentIndex: map['segment_index'] as int,
      isPrimary: (map['is_primary'] as int) == 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chapter_index': chapterIndex,
      'segment_index': segmentIndex,
      'is_primary': isPrimary ? 1 : 0,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'ChapterPosition(chapter: $chapterIndex, segment: $segmentIndex, primary: $isPrimary)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChapterPosition &&
        other.chapterIndex == chapterIndex &&
        other.segmentIndex == segmentIndex &&
        other.isPrimary == isPrimary;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, segmentIndex, isPrimary);
}
