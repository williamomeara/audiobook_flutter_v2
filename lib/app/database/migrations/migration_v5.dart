import 'package:sqflite/sqflite.dart';

/// Database migration version 5.
///
/// Removes content_confidence columns that were added in v4.
/// The Content Quality feature has been removed as it was redundant
/// with the BoilerplateRemover pipeline that already cleans text at import.
///
/// SQLite 3.35.0+ supports ALTER TABLE DROP COLUMN.
/// For older SQLite versions, these columns will just remain unused.
class MigrationV5 {
  /// Apply the migration.
  static Future<void> up(Database db) async {
    // Check SQLite version to see if DROP COLUMN is supported (3.35.0+)
    final versionResult = await db.rawQuery('SELECT sqlite_version()');
    final versionString = versionResult.first.values.first as String;
    final versionParts = versionString.split('.');
    final major = int.parse(versionParts[0]);
    final minor = int.parse(versionParts[1]);
    final supportsDropColumn = major > 3 || (major == 3 && minor >= 35);

    if (supportsDropColumn) {
      // Drop the content_confidence columns
      try {
        await db.execute('ALTER TABLE segments DROP COLUMN content_confidence');
      } catch (_) {
        // Column may not exist in some edge cases
      }

      try {
        await db.execute('ALTER TABLE chapters DROP COLUMN content_confidence');
      } catch (_) {
        // Column may not exist in some edge cases
      }

      try {
        await db
            .execute('ALTER TABLE books DROP COLUMN first_content_chapter');
      } catch (_) {
        // Column may not exist in some edge cases
      }
    }
    // If DROP COLUMN is not supported, the columns remain but are unused.
    // This is fine - they'll just be NULL and ignored by the app.
  }

  /// Rollback the migration (for testing).
  static Future<void> down(Database db) async {
    // Re-add the columns if needed
    try {
      await db.execute('ALTER TABLE segments ADD COLUMN content_confidence REAL');
    } catch (_) {
      // Column may already exist
    }

    try {
      await db.execute('ALTER TABLE chapters ADD COLUMN content_confidence REAL');
    } catch (_) {
      // Column may already exist
    }

    try {
      await db.execute(
          'ALTER TABLE books ADD COLUMN first_content_chapter INTEGER DEFAULT 0');
    } catch (_) {
      // Column may already exist
    }
  }
}
