import 'package:sqflite/sqflite.dart';

/// Database migration version 3.
///
/// Adds segment_progress table for per-segment listening tracking.
/// This enables:
/// - Chapter completion percentage calculation
/// - Resume at last heard segment
/// - Visual indication of listened vs unlistened segments
class MigrationV3 {
  /// Apply the migration.
  static Future<void> up(Database db) async {
    // Segment progress tracking - stores which segments have been listened to
    // Presence in this table = segment has been listened to
    await db.execute('''
      CREATE TABLE segment_progress (
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        listened_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter_index, segment_index)
      )
    ''');

    // Index for efficient chapter progress queries
    await db.execute('''
      CREATE INDEX idx_segment_progress_chapter 
      ON segment_progress(book_id, chapter_index)
    ''');
  }

  /// Rollback the migration (for testing).
  static Future<void> down(Database db) async {
    await db.execute('DROP INDEX IF EXISTS idx_segment_progress_chapter');
    await db.execute('DROP TABLE IF EXISTS segment_progress');
  }
}
