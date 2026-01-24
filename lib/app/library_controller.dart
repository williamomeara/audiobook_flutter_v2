import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:core_domain/core_domain.dart';

import '../infra/epub_parser.dart';
import '../infra/pdf_parser.dart';
import 'app_paths.dart';

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
class LibraryController extends AsyncNotifier<LibraryState> {
  static const _libraryFileName = 'library.json';

  @override
  Future<LibraryState> build() async {
    return _loadLibrary();
  }

  Future<Directory> _getAppDir() async {
    return await getApplicationDocumentsDirectory();
  }

  Future<File> _getLibraryFile() async {
    final dir = await _getAppDir();
    return File('${dir.path}/$_libraryFileName');
  }

  Future<LibraryState> _loadLibrary() async {
    try {
      final file = await _getLibraryFile();
      if (!await file.exists()) {
        return const LibraryState();
      }

      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      final booksList = (data['books'] as List<dynamic>? ?? [])
          .map((b) => Book.fromJson(b as Map<String, dynamic>))
          .toList();

      return LibraryState(books: booksList);
    } catch (e) {
      return LibraryState(error: 'Failed to load library: $e');
    }
  }

  Future<void> _saveLibrary(List<Book> books) async {
    try {
      final file = await _getLibraryFile();
      final data = {
        'books': books.map((b) => b.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      // Log error but don't fail
    }
  }

  Future<void> addBook(Book book) async {
    final current = state.value ?? const LibraryState();
    final updated = [book, ...current.books];
    state = AsyncValue.data(current.copyWith(books: updated));
    await _saveLibrary(updated);
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
      );

      final updated = [book, ...current.books];
      state = AsyncValue.data(current.copyWith(books: updated, isLoading: false));
      await _saveLibrary(updated);

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
    await _saveLibrary(updated);
  }

  Future<void> updateProgress(
    String bookId,
    int chapterIndex,
    int segmentIndex,
  ) async {
    final current = state.value ?? const LibraryState();
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
    await _saveLibrary(updated);
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
    await _saveLibrary(updated);
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
    await _saveLibrary(updated);
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
    await _saveLibrary(updated);
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
    await _saveLibrary(updated);
  }

  Book? getBook(String bookId) {
    return state.value?.books.where((b) => b.id == bookId).firstOrNull;
  }
}

/// Library provider.
final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);
