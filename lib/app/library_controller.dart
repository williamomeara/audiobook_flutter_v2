import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:core_domain/core_domain.dart';

import '../infra/epub_parser.dart';
import '../infra/pdf_parser.dart';
import '../infra/book_metadata_service.dart';
import '../utils/background_import.dart';
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

  /// Finds an imported book by title (to prevent duplicates).
  String? findByTitle(String title) {
    final current = state.value;
    if (current == null) return null;
    for (final b in current.books) {
      if (b.title == title) return b.id;
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
    String? overrideTitle,
    String? overrideAuthor,
  }) async {
    final current = state.value ?? const LibraryState();
    state = AsyncValue.data(current.copyWith(isLoading: true, error: null));

    try {
      if (gutenbergId != null) {
        final existing = findByGutenbergId(gutenbergId);
        if (existing != null) {
          // Book already exists - read current state for consistency
          final earlyExitState = state.value ?? const LibraryState();
          state = AsyncValue.data(earlyExitState.copyWith(isLoading: false));
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
      String? coverPath;  // Now mutable so we can update with API fallback
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

      // Try to look up better metadata from Google Books API
      String lookupTitle = title;
      String lookupAuthor = author;
      
      // For messy filenames, try to extract author from title pattern
      final metadataService = BookMetadataService();
      final isMessyFilename = _shouldLookupMetadata(title, author);
      
      if (isMessyFilename && author.toLowerCase().contains('unknown')) {
        // Try extracting author from filename pattern like "Title _Author Name_ _Z-Library_"
        final extractedAuthor = metadataService.extractAuthorFromTitle(title);
        if (extractedAuthor != null) {
          lookupAuthor = extractedAuthor;
        }
      }
      
      // Always try Google Books lookup for better metadata
      final metadata = await metadataService.searchBook(title, author);
      if (metadata != null) {
        // Use API data if we're confident enough
        // Lower threshold for messy filenames since we really need better data
        final confidenceThreshold = isMessyFilename ? 0.5 : 0.9;

        // Calculate confidence score
        final score = metadataService.calculateConfidence(metadata, title, author);
        if (score >= confidenceThreshold) {
          lookupTitle = metadata.title;
          lookupAuthor = metadata.authorsDisplay;
        }

        // If book file doesn't have a cover image, try to download from Google Books
        if (coverPath == null && metadata.thumbnailUrl != null) {
          try {
            final downloadedCover = await _downloadCoverImage(
              metadata.thumbnailUrl!,
              bookId,
            );
            if (downloadedCover != null) {
              coverPath = downloadedCover;
            }
          } catch (e) {
            // Silently fail - not having a cover isn't critical
            if (kDebugMode) debugPrint('Failed to download cover from Google Books: $e');
          }
        }
      }

      // Override with provided values if available (for Gutenberg imports)
      // But prefer Google Books data if it's very confident
      String finalTitle = lookupTitle;
      String finalAuthor = lookupAuthor;

      if (overrideTitle != null) {
        // For Gutenberg, use override unless Google Books is very confident
        final googleConfidence = metadata != null ? BookMetadataService().calculateConfidence(metadata, title, author) : 0.0;
        if (googleConfidence >= 0.95) {
          // Google Books is very confident, use its data
          finalTitle = metadata!.title;
          finalAuthor = metadata.authorsDisplay;
        } else {
          // Use Gutenberg override
          finalTitle = overrideTitle;
          finalAuthor = overrideAuthor ?? finalAuthor;
        }
      }

      // Check for duplicate book by title to prevent re-importing the same book
      final existingByTitle = findByTitle(finalTitle);
      if (existingByTitle != null) {
        // Book already exists - read current state for consistency
        final earlyExitState = state.value ?? const LibraryState();
        state = AsyncValue.data(earlyExitState.copyWith(isLoading: false));
        return existingByTitle;
      }

      // Pre-segment all chapters in background isolate to avoid UI jank
      // This moves CPU-intensive segmentation and scoring off main thread
      final segmentationResult = await runSegmentationInBackground(chapters);
      
      // Convert SegmentData back to Segment models
      final chapterSegments = segmentationResult.chapterSegments.map(
        (chapterSegs) => chapterSegs.map((s) => s.toSegment()).toList()
      ).toList();

      final book = Book(
        id: bookId,
        title: finalTitle,
        author: finalAuthor,
        filePath: destPath,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        coverImagePath: coverPath,
        chapters: chapters,
        gutenbergId: gutenbergId,
        progress: BookProgress.zero,
      );

      // Insert into SQLite with all segments
      final repo = await _getRepository();
      await repo.insertBook(book, chapterSegments);

      // Update in-memory state - read CURRENT state to avoid race condition
      // when multiple imports run concurrently
      final latestState = state.value ?? const LibraryState();
      final updated = [book, ...latestState.books];
      state = AsyncValue.data(latestState.copyWith(books: updated, isLoading: false));

      return bookId;
    } catch (e) {
      if (kDebugMode) debugPrint('Library import failed: $e');
      // Read current state to avoid race condition with concurrent imports
      final errorState = state.value ?? const LibraryState();
      state = AsyncValue.data(
        errorState.copyWith(isLoading: false, error: 'Import failed: $e'),
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
  Future<List<Segment>> getSegmentsForChapter(
      String bookId, int chapterIndex) async {
    final repo = await _getRepository();
    return await repo.getSegmentsForChapter(bookId, chapterIndex);
  }

  /// Get segment count for a chapter.
  Future<int> getSegmentCount(String bookId, int chapterIndex) async {
    final repo = await _getRepository();
    return await repo.getSegmentCount(bookId, chapterIndex);
  }

  /// Download cover image from Google Books API thumbnail URL.
  ///
  /// Downloads the thumbnail and saves it to the book's directory.
  /// Returns the path to the saved cover file, or null if download fails.
  Future<String?> _downloadCoverImage(String thumbnailUrl, String bookId) async {
    try {
      final response = await http.get(Uri.parse(thumbnailUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('Cover download failed: status ${response.statusCode}');
        return null;
      }

      // Determine file extension from URL or default to .jpg
      String ext = '.jpg';
      try {
        final uri = Uri.parse(thumbnailUrl);
        if (uri.pathSegments.isNotEmpty) {
          final lastSegment = uri.pathSegments.last;
          if (lastSegment.contains('.')) {
            final dotIndex = lastSegment.lastIndexOf('.');
            final potentialExt = lastSegment.substring(dotIndex);
            if (potentialExt.length <= 5 && potentialExt.startsWith('.')) {
              ext = potentialExt;
            }
          }
        }
      } catch (e) {
        // Use default .jpg if we can't parse
      }

      // Save the cover image
      final paths = await ref.read(appPathsProvider.future);
      final bookDir = paths.bookDir(bookId);
      await bookDir.create(recursive: true);

      final coverFile = File('${bookDir.path}/cover$ext');
      await coverFile.writeAsBytes(response.bodyBytes, flush: true);

      if (kDebugMode) debugPrint('Cover image downloaded from Google Books: ${coverFile.path}');
      return coverFile.path;
    } catch (e) {
      if (kDebugMode) debugPrint('Error downloading cover image: $e');
      return null;
    }
  }

  /// Check if we should attempt metadata lookup for this book.
  /// Looks for signs of unreliable metadata like extra annotations.
  bool _shouldLookupMetadata(String title, String author) {
    // ALWAYS try lookup if author is unknown - we WANT better metadata!
    if (author.toLowerCase().contains('unknown') || author.trim().isEmpty) {
      return true;  // Changed from false - unknown author means we need metadata!
    }

    // Look for common patterns that indicate messy metadata
    final messyPatterns = RegExp(r'\([^)]*(?:z-library|pdf|epub|kindle|azw|djvu)[^)]*\)', caseSensitive: false);
    if (messyPatterns.hasMatch(title)) {
      return true;
    }

    // Look for underscore-separated patterns like _Z-Library_
    final underscorePatterns = RegExp(r'_(?:z-library|pdf|epub|kindle|azw|djvu|libgen)_', caseSensitive: false);
    if (underscorePatterns.hasMatch(title)) {
      return true;
    }

    // Look for brackets with extra info
    final bracketPatterns = RegExp(r'\[[^\]]*(?:pdf|epub|kindle|azw|djvu)[^\]]*\]', caseSensitive: false);
    if (bracketPatterns.hasMatch(title)) {
      return true;
    }

    // Look for multiple parentheses (likely annotations)
    final parenCount = '('.allMatches(title).length;
    if (parenCount > 1) {
      return true;
    }

    return false;
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
