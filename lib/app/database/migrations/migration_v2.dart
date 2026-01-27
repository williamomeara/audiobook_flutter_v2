import 'package:sqflite/sqflite.dart';

/// Migration v2: Add missing columns to cache_entries for IntelligentCacheManager.
///
/// Adds:
/// - access_count: How many times the entry has been accessed
/// - engine_type: Which TTS engine generated this audio
/// - voice_id: Voice used (redundant with book but needed for cache manager)
class MigrationV2 {
  /// Apply the migration.
  static Future<void> up(Database db) async {
    // Add missing columns to cache_entries
    await db.execute('''
      ALTER TABLE cache_entries ADD COLUMN access_count INTEGER DEFAULT 1
    ''');

    await db.execute('''
      ALTER TABLE cache_entries ADD COLUMN engine_type TEXT
    ''');

    await db.execute('''
      ALTER TABLE cache_entries ADD COLUMN voice_id TEXT
    ''');

    // Create index on file_path for fast lookups by filename
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cache_file_path ON cache_entries(file_path)
    ''');
  }

  /// Rollback the migration (for testing).
  static Future<void> down(Database db) async {
    // SQLite doesn't support DROP COLUMN in older versions
    // In production, we'd recreate the table without these columns
    await db.execute('DROP INDEX IF EXISTS idx_cache_file_path');
  }
}
