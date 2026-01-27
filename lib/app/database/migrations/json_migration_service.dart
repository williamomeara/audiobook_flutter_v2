import 'dart:convert';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Service for migrating data from library.json to SQLite.
///
/// This is a one-time migration that runs on first app launch after
/// the SQLite update. It:
/// 1. Reads existing library.json
/// 2. Pre-segments all chapter content
/// 3. Inserts all data into SQLite
/// 4. Optionally backs up the original JSON file
class JsonMigrationService {
  static const String _libraryFileName = 'library.json';
  static const String _backupFileName = 'library.json.backup';

  /// Check if migration is needed (library.json exists but no books in DB).
  static Future<bool> needsMigration(Database db) async {
    final jsonFile = await _getLibraryFile();
    if (!await jsonFile.exists()) {
      return false;
    }

    // Check if DB has any books
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM books');
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count == 0;
  }

  /// Run the migration from library.json to SQLite.
  ///
  /// Returns the number of books migrated, or -1 on failure.
  static Future<int> migrate(Database db) async {
    final jsonFile = await _getLibraryFile();
    if (!await jsonFile.exists()) {
      if (kDebugMode) debugPrint('No library.json found, skipping migration');
      return 0;
    }

    try {
      // Read and parse library.json
      final json = await jsonFile.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      final booksList = (data['books'] as List<dynamic>? ?? [])
          .map((b) => Book.fromJson(b as Map<String, dynamic>))
          .toList();

      if (booksList.isEmpty) {
        if (kDebugMode) debugPrint('No books in library.json');
        return 0;
      }

      if (kDebugMode) {
        debugPrint('Migrating ${booksList.length} books from library.json');
      }

      // Migrate all books in a single transaction
      await db.transaction((txn) async {
        for (final book in booksList) {
          await _migrateBook(txn, book);
        }
      });

      // Create backup and delete original
      await _backupAndDelete(jsonFile);

      if (kDebugMode) {
        debugPrint('Successfully migrated ${booksList.length} books');
      }
      return booksList.length;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('Migration failed: $e');
        debugPrint('$stack');
      }
      return -1;
    }
  }

  /// Migrate a single book with all its chapters and segments.
  static Future<void> _migrateBook(Transaction txn, Book book) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Insert book
    await txn.insert('books', {
      'id': book.id,
      'title': book.title,
      'author': book.author,
      'file_path': book.filePath,
      'cover_image_path': book.coverImagePath,
      'gutenberg_id': book.gutenbergId,
      'voice_id': book.voiceId,
      'is_favorite': book.isFavorite ? 1 : 0,
      'added_at': book.addedAt,
      'updated_at': now,
    });

    // Insert chapters and segments
    for (var chapterIndex = 0;
        chapterIndex < book.chapters.length;
        chapterIndex++) {
      final chapter = book.chapters[chapterIndex];

      // Pre-segment the chapter content
      final segments = segmentText(chapter.content);

      // Calculate chapter stats
      final charCount = chapter.content.length;
      final wordCount = (charCount / 5).round();
      final durationMs = segments.fold<int>(
          0, (sum, s) => sum + (s.estimatedDurationMs ?? estimateDurationMs(s.text)));

      // Insert chapter metadata
      await txn.insert('chapters', {
        'book_id': book.id,
        'chapter_index': chapterIndex,
        'title': chapter.title,
        'segment_count': segments.length,
        'word_count': wordCount,
        'char_count': charCount,
        'estimated_duration_ms': durationMs,
      });

      // Batch insert segments for efficiency
      final batch = txn.batch();
      for (final segment in segments) {
        batch.insert('segments', {
          'book_id': book.id,
          'chapter_index': chapterIndex,
          'segment_index': segment.index,
          'text': segment.text,
          'char_count': segment.text.length,
          'estimated_duration_ms':
              segment.estimatedDurationMs ?? estimateDurationMs(segment.text),
        });
      }
      await batch.commit(noResult: true);
    }

    // Insert reading progress
    await txn.insert('reading_progress', {
      'book_id': book.id,
      'chapter_index': book.progress.chapterIndex,
      'segment_index': book.progress.segmentIndex,
      'total_listen_time_ms': 0,
      'updated_at': now,
    });

    // Insert completed chapters
    for (final chapterIdx in book.completedChapters) {
      await txn.insert('completed_chapters', {
        'book_id': book.id,
        'chapter_index': chapterIdx,
        'completed_at': now,
      });
    }
  }

  /// Backup the original file and delete it.
  static Future<void> _backupAndDelete(File jsonFile) async {
    try {
      final backupPath =
          jsonFile.path.replaceAll(_libraryFileName, _backupFileName);
      await jsonFile.copy(backupPath);
      await jsonFile.delete();
      if (kDebugMode) {
        debugPrint('Backed up library.json to $backupPath');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to backup/delete library.json: $e');
      }
      // Don't fail the migration for backup errors
    }
  }

  static Future<File> _getLibraryFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_libraryFileName');
  }
}
