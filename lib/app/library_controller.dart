import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:core_domain/core_domain.dart';

import '../infra/epub_parser.dart';
import '../infra/pdf_parser.dart';
import '../utils/segment_confidence_scorer.dart';
import 'app_paths.dart';
import 'database/app_database.dart';
import 'database/repositories/library_repository.dart';

/// Library state containing all books.
class LibraryState {
  const LibraryState({
    this.books = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Book> books;
  final bool isLoading;
  final String? error;

  LibraryState copyWith({
    List<Book>? books,
    bool? isLoading,
    String? error,
  }) {
    return LibraryState(
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Library controller for managing books.
///
/// Uses SQLite for persistence via LibraryRepository.
/// All data operations are atomic and fast (indexed queries).
class LibraryController extends AsyncNotifier<LibraryState> {
  LibraryRepository? _repository;

  @override
  Future<LibraryState> build() async {
    return _loadLibrary();
  }

  Future<LibraryRepository> _getRepository() async {
    if (_repository != null) return _repository!;
    final db = await AppDatabase.instance;
    _repository = LibraryRepository(db);
    return _repository!;
  }

  Future<LibraryState> _loadLibrary() async {
    try {
      final repo = await _getRepository();
      final books = await repo.getAllBooks();
      return LibraryState(books: books);
    } catch (e) {
      return LibraryState(error: 'Failed to load library: $e');
    }
  }

  Future<void> addBook(Book book) async {
    final current = state.value ?? const LibraryState();
    final updated = [book, ...current.books];
    state = AsyncValue.data(current.copyWith(books: updated));
    // Note: For addBook without segments, we need the import flow
    // This method is kept for API compatibility but import should use importBookFromPath
  }

  /// Finds an imported book by Project Gutenberg id.
  String? findByGutenbergId(int gutenbergId) {
    final current = state.value;
    if (current == null) return null;
    for (final b in current.books) {
      if (b.gutenbergId == gutenbergId) return b.id;
    }
    return null;
  }

  /// Import an EPUB or PDF file into the app's book storage, parse it, and add to library.
  ///
  /// Returns the created (or existing) bookId.
  /// Pre-segments all chapters at import time for fast playback.
  Future<String> importBookFromPath({
    required String sourcePath,
    required String fileName,
    int? gutenbergId,
  }) async {
    final current = state.value ?? const LibraryState();
    state = AsyncValue.data(current.copyWith(isLoading: true, error: null));

    try {
      if (gutenbergId != null) {
        final existing = findByGutenbergId(gutenbergId);
        if (existing != null) {
          state = AsyncValue.data(current.copyWith(isLoading: false));
          return existing;
        }
      }

      final lower = fileName.toLowerCase();
      final isEpub = lower.endsWith('.epub');
      final isPdf = lower.endsWith('.pdf');
      if (!isEpub && !isPdf) {
        throw Exception('Unsupported file format. Please select an EPUB or PDF file.');
      }

      final bookId = IdGenerator.generateBookId();
      final paths = await ref.read(appPathsProvider.future);

      final bookDir = paths.bookDir(bookId);
      await bookDir.create(recursive: true);

      final safeName = _sanitizeFileName(fileName, isPdf: isPdf);
      final destPath = '${bookDir.path}/$safeName';
      await File(sourcePath).copy(destPath);

      // Parse based on file type
      final String title;
      final String author;
      final String? coverPath;
      final List<Chapter> chapters;

      if (isPdf) {
        final parser = await ref.read(pdfParserProvider.future);
        final parsed = await parser.parseFromFile(pdfPath: destPath, bookId: bookId);
        title = parsed.title;
        author = parsed.author;
        coverPath = parsed.coverPath;
        chapters = parsed.chapters;
      } else {
        final parser = await ref.read(epubParserProvider.future);
        final parsed = await parser.parseFromFile(epubPath: destPath, bookId: bookId);
        title = parsed.title;
        author = parsed.author;
        coverPath = parsed.coverPath;
        chapters = parsed.chapters;
      }

      // Pre-segment all chapters at import time with confidence scoring
      final chapterSegments = <List<Segment>>[];
      for (final chapter in chapters) {
        final segments = segmentText(chapter.content);
        // Add duration estimates and confidence scores
        final segmentsWithMetadata = segments.map((s) => Segment(
          text: s.text,
          index: s.index,
          estimatedDurationMs: estimateDurationMs(s.text),
          contentConfidence: SegmentConfidenceScorer.scoreSegment(s.text),
        )).toList();
        chapterSegments.add(segmentsWithMetadata);
      }

      // Find the first chapter that appears to be actual content
      final firstContentChapter = SegmentConfidenceScorer.findFirstContentChapter(
        chapterSegments,
        threshold: 0.5,
      );

      final book = Book(
        id: bookId,
        title: title,
        author: author,
        filePath: destPath,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        coverImagePath: coverPath,
        chapters: chapters,
        gutenbergId: gutenbergId,
        progress: BookProgress.zero,
        firstContentChapter: firstContentChapter,
      );

      // Insert into SQLite with all segments
      final repo = await _getRepository();
      await repo.insertBook(book, chapterSegments);

      // Update in-memory state
      final updated = [book, ...current.books];
      state = AsyncValue.data(current.copyWith(books: updated, isLoading: false));

      return bookId;
    } catch (e) {
      if (kDebugMode) debugPrint('Library import failed: $e');
      state = AsyncValue.data(
        current.copyWith(isLoading: false, error: 'Import failed: $e'),
      );
      rethrow;
    }
  }

  String _sanitizeFileName(String name, {bool isPdf = false}) {
    final ext = isPdf ? '.pdf' : '.epub';
    final trimmed = name.trim().isEmpty ? 'book$ext' : name.trim();
    final withoutBadChars = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]+'), '_');
    var out = withoutBadChars;
    if (!out.toLowerCase().endsWith(ext)) out = '$out$ext';
    if (out.length > 160) out = '${out.substring(0, 160)}$ext';
    return out;
  }

  Future<void> removeBook(String bookId) async {
    final current = state.value ?? const LibraryState();
    final updated = current.books.where((b) => b.id != bookId).toList();
    state = AsyncValue.data(current.copyWith(books: updated));

    final repo = await _getRepository();
    await repo.deleteBook(bookId);
  }

  Future<void> updateProgress(
    String bookId,
    int chapterIndex,
    int segmentIndex,
  ) async {
    final current = state.value ?? const LibraryState();

    // Update in-memory state
    final updated = current.books.map((b) {
      if (b.id == bookId) {
        return b.copyWith(
          progress: BookProgress(
            chapterIndex: chapterIndex,
            segmentIndex: segmentIndex,
          ),
        );
      }
      return b;
    }).toList();
    state = AsyncValue.data(current.copyWith(books: updated));

    // Persist to SQLite (fast indexed update)
    final repo = await _getRepository();
    await repo.updateProgress(bookId, chapterIndex, segmentIndex);
  }

  Future<void> setBookVoice(String bookId, String? voiceId) async {
    final current = state.value ?? const LibraryState();

    final updated = current.books.map((b) {
      if (b.id == bookId) {
        return b.copyWith(voiceId: voiceId);
      }
      return b;
    }).toList();
    state = AsyncValue.data(current.copyWith(books: updated));

    final repo = await _getRepository();
    await repo.setBookVoice(bookId, voiceId);
  }

  Future<void> toggleFavorite(String bookId) async {
    final current = state.value ?? const LibraryState();

    final updated = current.books.map((b) {
      if (b.id == bookId) {
        return b.copyWith(isFavorite: !b.isFavorite);
      }
      return b;
    }).toList();
    state = AsyncValue.data(current.copyWith(books: updated));

    final repo = await _getRepository();
    await repo.toggleFavorite(bookId);
  }

  /// Mark a chapter as completed (listened to >95%).
  Future<void> markChapterComplete(String bookId, int chapterIndex) async {
    final current = state.value ?? const LibraryState();

    final updated = current.books.map((b) {
      if (b.id == bookId) {
        final newCompleted = Set<int>.from(b.completedChapters)..add(chapterIndex);
        return b.copyWith(completedChapters: newCompleted);
      }
      return b;
    }).toList();
    state = AsyncValue.data(current.copyWith(books: updated));

    final repo = await _getRepository();
    await repo.markChapterComplete(bookId, chapterIndex);
  }

  /// Toggle a chapter's read/unread state manually.
  Future<void> toggleChapterComplete(String bookId, int chapterIndex) async {
    final current = state.value ?? const LibraryState();

    final updated = current.books.map((b) {
      if (b.id == bookId) {
        final newCompleted = Set<int>.from(b.completedChapters);
        if (newCompleted.contains(chapterIndex)) {
          newCompleted.remove(chapterIndex);
        } else {
          newCompleted.add(chapterIndex);
        }
        return b.copyWith(completedChapters: newCompleted);
      }
      return b;
    }).toList();
    state = AsyncValue.data(current.copyWith(books: updated));

    final repo = await _getRepository();
    await repo.toggleChapterComplete(bookId, chapterIndex);
  }

  Book? getBook(String bookId) {
    return state.value?.books.where((b) => b.id == bookId).firstOrNull;
  }

  /// Get segments for a chapter (for playback).
  /// This is the new way to get segment data - from SQLite, not runtime segmentation.
  /// 
  /// If [minConfidence] is provided, filters out low-confidence segments.
  Future<List<Segment>> getSegmentsForChapter(
      String bookId, int chapterIndex, {double? minConfidence}) async {
    final repo = await _getRepository();
    return await repo.getSegmentsForChapter(
      bookId, 
      chapterIndex,
      minConfidence: minConfidence,
    );
  }

  /// Get segment count for a chapter.
  Future<int> getSegmentCount(String bookId, int chapterIndex) async {
    final repo = await _getRepository();
    return await repo.getSegmentCount(bookId, chapterIndex);
  }
}

/// Library provider.
final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

/// Provider for getting segments from SQLite.
/// Use this instead of runtime segmentText() calls.
final segmentsProvider = FutureProvider.family<List<Segment>, ({String bookId, int chapterIndex})>(
  (ref, params) async {
    final controller = ref.read(libraryProvider.notifier);
    return await controller.getSegmentsForChapter(params.bookId, params.chapterIndex);
  },
);
