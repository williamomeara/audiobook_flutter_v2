import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:core_domain/core_domain.dart';

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
    final updated = [...current.books, book];
    state = AsyncValue.data(current.copyWith(books: updated));
    await _saveLibrary(updated);
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

  Book? getBook(String bookId) {
    return state.value?.books.where((b) => b.id == bookId).firstOrNull;
  }
}

/// Library provider.
final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);
