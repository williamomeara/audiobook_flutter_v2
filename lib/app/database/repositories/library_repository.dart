import 'dart:convert';

import 'package:core_domain/core_domain.dart';
import 'package:sqflite/sqflite.dart';

import '../daos/book_dao.dart';
import '../daos/chapter_dao.dart';
import '../daos/completed_chapters_dao.dart';
import '../daos/progress_dao.dart';
import '../daos/segment_dao.dart';

/// Repository for library operations using SQLite.
///
/// This is the single source of truth for book data.
/// Coordinates multiple DAOs for complex operations.
class LibraryRepository {
  final Database _db;
  late final BookDao _bookDao;
  late final ChapterDao _chapterDao;
  late final SegmentDao _segmentDao;
  late final ProgressDao _progressDao;
  late final CompletedChaptersDao _completedChaptersDao;

  LibraryRepository(this._db) {
    _bookDao = BookDao(_db);
    _chapterDao = ChapterDao(_db);
    _segmentDao = SegmentDao(_db);
    _progressDao = ProgressDao(_db);
    _completedChaptersDao = CompletedChaptersDao(_db);
  }

  /// Get all books with their progress (no chapters/segments loaded).
  Future<List<Book>> getAllBooks() async {
    final bookRows = await _bookDao.getAllBooks();
    final books = <Book>[];

    for (final row in bookRows) {
      final bookId = row['id'] as String;

      // Load chapter metadata (not segments)
      final chapterRows = await _chapterDao.getChaptersForBook(bookId);
      final chapters = chapterRows.map((ch) => Chapter(
        id: '${bookId}_ch${ch['chapter_index']}',
        number: (ch['chapter_index'] as int) + 1,
        title: ch['title'] as String,
        content: '', // Content is in segments, not loaded here
      )).toList();

      // Load progress
      final progressRow = await _progressDao.getProgress(bookId);
      final progress = progressRow != null
          ? BookProgress(
              chapterIndex: progressRow['chapter_index'] as int,
              segmentIndex: progressRow['segment_index'] as int,
            )
          : BookProgress.zero;

      // Load completed chapters
      final completedChapters =
          await _completedChaptersDao.getCompletedChapters(bookId);

      books.add(Book(
        id: bookId,
        title: row['title'] as String,
        author: row['author'] as String,
        filePath: row['file_path'] as String,
        addedAt: row['added_at'] as int,
        gutenbergId: row['gutenberg_id'] as int?,
        coverImagePath: row['cover_image_path'] as String?,
        voiceId: row['voice_id'] as String?,
        isFavorite: (row['is_favorite'] as int) == 1,
        chapters: chapters,
        progress: progress,
        completedChapters: completedChapters,
      ));
    }

    return books;
  }

  /// Get a single book by ID with full chapter metadata.
  Future<Book?> getBook(String bookId) async {
    final row = await _bookDao.getBook(bookId);
    if (row == null) return null;

    final chapterRows = await _chapterDao.getChaptersForBook(bookId);
    final chapters = chapterRows.map((ch) => Chapter(
      id: '${bookId}_ch${ch['chapter_index']}',
      number: (ch['chapter_index'] as int) + 1,
      title: ch['title'] as String,
      content: '', // Content is in segments
    )).toList();

    final progressRow = await _progressDao.getProgress(bookId);
    final progress = progressRow != null
        ? BookProgress(
            chapterIndex: progressRow['chapter_index'] as int,
            segmentIndex: progressRow['segment_index'] as int,
          )
        : BookProgress.zero;

    final completedChapters =
        await _completedChaptersDao.getCompletedChapters(bookId);

    return Book(
      id: bookId,
      title: row['title'] as String,
      author: row['author'] as String,
      filePath: row['file_path'] as String,
      addedAt: row['added_at'] as int,
      gutenbergId: row['gutenberg_id'] as int?,
      coverImagePath: row['cover_image_path'] as String?,
      voiceId: row['voice_id'] as String?,
      isFavorite: (row['is_favorite'] as int) == 1,
      chapters: chapters,
      progress: progress,
      completedChapters: completedChapters,
    );
  }

  /// Get segments for a chapter (for playback).
  Future<List<Segment>> getSegmentsForChapter(
      String bookId, int chapterIndex) async {
    final rows = await _segmentDao.getSegmentsForChapter(bookId, chapterIndex);
    return rows.map((row) {
      // Parse segment type from string
      final typeStr = row['segment_type'] as String? ?? 'text';
      final type = _parseSegmentType(typeStr);
      
      // Parse metadata from JSON
      final metadataJson = row['metadata_json'] as String?;
      Map<String, dynamic>? metadata;
      if (metadataJson != null && metadataJson.isNotEmpty) {
        try {
          metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
        } catch (e) {
          // Ignore malformed JSON
        }
      }
      
      return Segment(
        text: row['text'] as String,
        index: row['segment_index'] as int,
        estimatedDurationMs: row['estimated_duration_ms'] as int?,
        type: type,
        metadata: metadata,
      );
    }).toList();
  }
  
  /// Parse segment type from database string value.
  SegmentType _parseSegmentType(String value) {
    switch (value) {
      case 'figure': return SegmentType.figure;
      case 'heading': return SegmentType.heading;
      case 'quote': return SegmentType.quote;
      default: return SegmentType.text;
    }
  }

  /// Get a single segment's text (optimized for TTS).
  Future<String?> getSegmentText(
      String bookId, int chapterIndex, int segmentIndex) async {
    return await _segmentDao.getSegmentText(bookId, chapterIndex, segmentIndex);
  }

  /// Get segment count for a chapter.
  Future<int> getSegmentCount(String bookId, int chapterIndex) async {
    return await _segmentDao.getSegmentCount(bookId, chapterIndex);
  }

  /// Insert a new book with chapters and segments (used during import).
  /// All operations are wrapped in a transaction.
  Future<void> insertBook(Book book, List<List<Segment>> chapterSegments) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
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
        final segments = chapterSegments[chapterIndex];

        // Calculate chapter stats from segments
        final charCount =
            segments.fold<int>(0, (sum, s) => sum + s.text.length);
        final wordCount = (charCount / 5).round();
        final durationMs = segments.fold<int>(
            0, (sum, s) => sum + (s.estimatedDurationMs ?? 0));

        // Determine if chapter is playable (has enough content for TTS)
        // A chapter is non-playable if it has no segments or very few words
        // (likely a structural divider like "PART I" or "ACT I")
        const minPlayableWordCount = 5;
        final isPlayable = segments.isNotEmpty && wordCount >= minPlayableWordCount;

        // Insert chapter metadata
        await txn.insert('chapters', {
          'book_id': book.id,
          'chapter_index': chapterIndex,
          'title': chapter.title,
          'segment_count': segments.length,
          'word_count': wordCount,
          'char_count': charCount,
          'estimated_duration_ms': durationMs,
          'is_playable': isPlayable ? 1 : 0,
        });

        // Batch insert segments
        final batch = txn.batch();
        for (final segment in segments) {
          // Encode metadata to JSON if present
          String? metadataJson;
          if (segment.metadata != null && segment.metadata!.isNotEmpty) {
            metadataJson = jsonEncode(segment.metadata);
          }
          
          batch.insert('segments', {
            'book_id': book.id,
            'chapter_index': chapterIndex,
            'segment_index': segment.index,
            'text': segment.text,
            'char_count': segment.text.length,
            'estimated_duration_ms':
                segment.estimatedDurationMs ?? estimateDurationMs(segment.text),
            'segment_type': segment.type.name,
            'metadata_json': metadataJson,
          });
        }
        await batch.commit(noResult: true);
      }

      // Insert initial progress
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
    });
  }

  /// Delete a book and all related data (cascades via FK).
  Future<void> deleteBook(String bookId) async {
    await _bookDao.deleteBook(bookId);
  }

  /// Update reading progress.
  Future<void> updateProgress(
      String bookId, int chapterIndex, int segmentIndex) async {
    await _progressDao.updatePosition(bookId, chapterIndex, segmentIndex);
  }

  /// Update book voice.
  Future<void> setBookVoice(String bookId, String? voiceId) async {
    await _bookDao.updateVoice(bookId, voiceId ?? '');
  }

  /// Toggle favorite status.
  Future<void> toggleFavorite(String bookId) async {
    await _bookDao.toggleFavorite(bookId);
  }

  /// Mark a chapter as complete.
  Future<void> markChapterComplete(String bookId, int chapterIndex) async {
    await _completedChaptersDao.markChapterComplete(bookId, chapterIndex);
  }

  /// Toggle chapter completion.
  Future<bool> toggleChapterComplete(String bookId, int chapterIndex) async {
    return await _completedChaptersDao.toggleChapterComplete(
        bookId, chapterIndex);
  }

  /// Check if a book exists.
  Future<bool> bookExists(String bookId) async {
    return await _bookDao.exists(bookId);
  }

  /// Find book by Gutenberg ID.
  Future<String?> findByGutenbergId(int gutenbergId) async {
    final result = await _db.query(
      'books',
      columns: ['id'],
      where: 'gutenberg_id = ?',
      whereArgs: [gutenbergId],
      limit: 1,
    );
    return result.isEmpty ? null : result.first['id'] as String;
  }

  /// Get chapter content by joining all segments (for full text display).
  Future<String> getChapterContent(String bookId, int chapterIndex) async {
    final texts = await _segmentDao.getChapterTexts(bookId, chapterIndex);
    return texts.join('\n\n');
  }

  /// Add listen time to a book.
  Future<void> addListenTime(String bookId, int durationMs) async {
    await _progressDao.addListenTime(bookId, durationMs);
  }

  /// Check if a chapter is playable (has audio content).
  /// Non-playable chapters are structural dividers like "PART I" or "ACT I".
  Future<bool> isChapterPlayable(String bookId, int chapterIndex) async {
    return await _chapterDao.isChapterPlayable(bookId, chapterIndex);
  }

  /// Find the next playable chapter index starting from (but not including) the given index.
  /// Returns null if no playable chapter exists after the given index.
  Future<int?> findNextPlayableChapter(String bookId, int fromIndex) async {
    return await _chapterDao.findNextPlayableChapter(bookId, fromIndex);
  }

  /// Find the previous playable chapter index starting from (but not including) the given index.
  /// Returns null if no playable chapter exists before the given index.
  Future<int?> findPreviousPlayableChapter(String bookId, int fromIndex) async {
    return await _chapterDao.findPreviousPlayableChapter(bookId, fromIndex);
  }

  /// Find the first playable chapter for a book.
  /// Returns null if no playable chapters exist.
  Future<int?> findFirstPlayableChapter(String bookId) async {
    return await _chapterDao.findFirstPlayableChapter(bookId);
  }
}
