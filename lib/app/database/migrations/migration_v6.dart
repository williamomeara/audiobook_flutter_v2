import 'package:sqflite/sqflite.dart';

/// Database migration version 6.
///
/// Adds chapter_positions table for per-chapter resume functionality.
/// This enables:
/// - Remembering listening position within each visited chapter
/// - "Snap back" to primary listening position after browsing
/// - Smooth chapter-to-chapter navigation without losing place
///
/// Table schema:
/// - book_id: Foreign key to books table
/// - chapter_index: Which chapter this position is for
/// - segment_index: The segment position within the chapter
/// - is_primary: Boolean flag for the main listening position
/// - updated_at: Timestamp for last update
class MigrationV6 {
  /// Apply the migration.
  static Future<void> up(Database db) async {
    // Create chapter_positions table
    await db.execute('''
      CREATE TABLE chapter_positions (
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, chapter_index),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    // Index for quick primary position lookup
    await db.execute('''
      CREATE INDEX idx_chapter_positions_primary 
      ON chapter_positions(book_id) 
      WHERE is_primary = 1
    ''');
  }

  /// Rollback the migration (for testing).
  static Future<void> down(Database db) async {
    await db.execute('DROP INDEX IF EXISTS idx_chapter_positions_primary');
    await db.execute('DROP TABLE IF EXISTS chapter_positions');
  }
}
