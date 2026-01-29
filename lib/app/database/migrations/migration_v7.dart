import 'package:sqflite/sqflite.dart';

/// Migration V7: Add compression state tracking columns to cache_entries
///
/// Adds missing columns needed for proper audio cache compression tracking:
/// - compression_state: Tracks the compression state (wav, m4a, compressing, failed)
/// - compression_started_at: Tracks when compression operation started
///
/// This migration is necessary because the consolidated migration didn't apply
/// to existing databases. These columns are critical for the compression service
/// to function correctly.
class MigrationV7 {
  static Future<void> up(Database db) async {
    // Add compression_state column if it doesn't exist
    // Check if column exists by trying to query it
    try {
      await db.rawQuery('SELECT compression_state FROM cache_entries LIMIT 1');
    } catch (e) {
      // Column doesn't exist, add it
      await db.execute('''
        ALTER TABLE cache_entries ADD COLUMN compression_state TEXT DEFAULT 'wav'
      ''');
    }

    // Add compression_started_at column if it doesn't exist
    try {
      await db.rawQuery('SELECT compression_started_at FROM cache_entries LIMIT 1');
    } catch (e) {
      // Column doesn't exist, add it
      await db.execute('''
        ALTER TABLE cache_entries ADD COLUMN compression_started_at INTEGER
      ''');
    }

    // Insert the schema version record
    await db.insert('schema_version', {
      'version': 7,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
      'description': 'Added compression state tracking columns (V7)',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
