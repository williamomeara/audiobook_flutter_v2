import 'package:sqflite/sqflite.dart';

/// Migration V9: Add is_playable column to chapters table
///
/// This migration adds support for marking chapters as non-playable when they:
/// - Have no segments (empty structural chapters like "PART I")
/// - Contain only images (no readable text)
/// - Have HTML remnants with no real content
///
/// The is_playable column enables:
/// - Auto-skipping empty chapters during playback navigation
/// - Visual indication in chapter list UI
/// - Better UX for books with structural dividers
class MigrationV9 {
  /// Minimum word count for a chapter to be considered playable.
  /// Chapters with fewer words are considered structural/divider chapters.
  static const int minPlayableWordCount = 5;

  static Future<void> up(Database db) async {
    // Add is_playable column if it doesn't exist
    try {
      await db.rawQuery('SELECT is_playable FROM chapters LIMIT 1');
    } catch (e) {
      // Column doesn't exist, add it
      // Default to 1 (true) for existing chapters - they'll be backfilled below
      await db.execute('''
        ALTER TABLE chapters ADD COLUMN is_playable INTEGER DEFAULT 1 NOT NULL
      ''');
    }

    // Backfill: Mark chapters as non-playable if they meet any of these criteria:
    // 1. segment_count = 0 (no segments at all)
    // 2. word_count < minPlayableWordCount (likely structural divider or HTML remnant)
    // 3. word_count is NULL (edge case - treat as empty)
    await db.execute('''
      UPDATE chapters 
      SET is_playable = 0 
      WHERE segment_count = 0 
         OR word_count IS NULL 
         OR word_count < $minPlayableWordCount
    ''');

    // Insert the schema version record
    await db.insert(
      'schema_version',
      {
        'version': 9,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
        'description': 'Added is_playable column to chapters (V9)',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> down(Database db) async {
    // SQLite doesn't support dropping columns directly
    // Would need to recreate the table without the column
    // For simplicity, we leave the column in place
  }
}
