import 'package:sqflite/sqflite.dart';

/// Database migration version 4.
///
/// Adds content_confidence column to segments table for smart content detection.
/// This enables:
/// - Identifying front matter vs actual story content
/// - Offering users the option to skip to first chapter
/// - Visual indication of content confidence in chapter list
class MigrationV4 {
  /// Apply the migration.
  static Future<void> up(Database db) async {
    // Add content_confidence column to segments table
    // Default to null (not scored) for existing data
    await db.execute('''
      ALTER TABLE segments ADD COLUMN content_confidence REAL
    ''');

    // Add content_confidence column to chapters table for aggregated score
    await db.execute('''
      ALTER TABLE chapters ADD COLUMN content_confidence REAL
    ''');

    // Add first_content_chapter to books for quick lookup
    await db.execute('''
      ALTER TABLE books ADD COLUMN first_content_chapter INTEGER DEFAULT 0
    ''');
  }

  /// Rollback the migration (for testing).
  static Future<void> down(Database db) async {
    // SQLite doesn't support DROP COLUMN directly, so we'd need to recreate tables
    // For now, just leave the columns (they'll be ignored if not used)
    // In production, you'd need a full table recreation strategy
  }
}
