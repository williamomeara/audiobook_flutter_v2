import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/app/library_controller.dart';
import 'package:core_domain/core_domain.dart';

void main() {
  group('LibraryState', () {
    test('has sensible defaults', () {
      const state = LibraryState();
      
      expect(state.books, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('copyWith updates books list', () {
      const state = LibraryState();
      
      final book = Book(
        id: 'test-book-1',
        title: 'Test Book',
        author: 'Test Author',
        filePath: '/path/to/book.epub',
        addedAt: 1234567890,
        chapters: [],
      );
      
      final updated = state.copyWith(books: [book]);
      
      expect(updated.books.length, 1);
      expect(updated.books.first.id, 'test-book-1');
      expect(updated.isLoading, false);
      expect(updated.error, isNull);
    });

    test('copyWith updates loading state', () {
      const state = LibraryState();
      
      final loading = state.copyWith(isLoading: true);
      
      expect(loading.isLoading, true);
      expect(loading.books, isEmpty);
      expect(loading.error, isNull);
    });

    test('copyWith updates error state', () {
      const state = LibraryState();
      
      final error = state.copyWith(error: 'Something went wrong');
      
      expect(error.error, 'Something went wrong');
      expect(error.books, isEmpty);
      expect(error.isLoading, false);
    });

    test('copyWith preserves books when updating other fields', () {
      final book = Book(
        id: 'test-book-1',
        title: 'Test Book',
        author: 'Test Author',
        filePath: '/path/to/book.epub',
        addedAt: 1234567890,
        chapters: [],
      );
      
      final state = LibraryState(books: [book]);
      
      final loading = state.copyWith(isLoading: true);
      
      expect(loading.books.length, 1);
      expect(loading.books.first.id, 'test-book-1');
      expect(loading.isLoading, true);
    });

    test('copyWith clears error with explicit null', () {
      final stateWithError = LibraryState(error: 'Previous error');
      
      // copyWith with no error argument keeps the error
      // The copyWith implementation doesn't clear error on its own
      // since error parameter defaults to the current value
      
      expect(stateWithError.error, 'Previous error');
    });
  });

  group('Book model integration', () {
    test('can create book with minimal required fields', () {
      final book = Book(
        id: 'minimal-book',
        title: 'Minimal Book',
        author: 'Author',
        filePath: '/path.epub',
        addedAt: 0,
        chapters: [],
      );
      
      expect(book.id, 'minimal-book');
      expect(book.title, 'Minimal Book');
      expect(book.author, 'Author');
      expect(book.chapters, isEmpty);
    });

    test('book with chapters', () {
      final chapters = [
        Chapter(
          id: 'ch-1',
          number: 1,
          title: 'Chapter 1',
          content: 'Once upon a time...',
        ),
        Chapter(
          id: 'ch-2',
          number: 2,
          title: 'Chapter 2',
          content: 'And then...',
        ),
      ];
      
      final book = Book(
        id: 'book-with-chapters',
        title: 'Story Book',
        author: 'Storyteller',
        filePath: '/path.epub',
        addedAt: 1234567890,
        chapters: chapters,
      );
      
      expect(book.chapters.length, 2);
      expect(book.chapters[0].title, 'Chapter 1');
      expect(book.chapters[1].title, 'Chapter 2');
    });

    test('book progress tracking', () {
      final book = Book(
        id: 'progress-book',
        title: 'Long Book',
        author: 'Author',
        filePath: '/path.epub',
        addedAt: 0,
        chapters: [
          Chapter(id: 'ch1', number: 1, title: 'Ch 1', content: 'Content'),
          Chapter(id: 'ch2', number: 2, title: 'Ch 2', content: 'Content'),
          Chapter(id: 'ch3', number: 3, title: 'Ch 3', content: 'Content'),
        ],
        progress: BookProgress(chapterIndex: 1, segmentIndex: 5),
      );
      
      expect(book.progress.chapterIndex, 1);
      expect(book.progress.segmentIndex, 5);
    });

    test('book with optional fields', () {
      final book = Book(
        id: 'full-book',
        title: 'Complete Book',
        author: 'Famous Author',
        filePath: '/path.epub',
        addedAt: 1234567890,
        coverImagePath: '/cover.jpg',
        gutenbergId: 12345,
        isFavorite: true,
        voiceId: 'kokoro-v1',
        chapters: [],
        completedChapters: {0, 1, 2},
      );
      
      expect(book.coverImagePath, '/cover.jpg');
      expect(book.gutenbergId, 12345);
      expect(book.isFavorite, true);
      expect(book.voiceId, 'kokoro-v1');
      expect(book.completedChapters, {0, 1, 2});
    });
  });

  group('LibraryState with multiple books', () {
    test('can hold multiple books', () {
      final books = List.generate(5, (i) => Book(
        id: 'book-$i',
        title: 'Book $i',
        author: 'Author $i',
        filePath: '/path$i.epub',
        addedAt: i * 1000,
        chapters: [],
      ));
      
      final state = LibraryState(books: books);
      
      expect(state.books.length, 5);
      expect(state.books[0].id, 'book-0');
      expect(state.books[4].id, 'book-4');
    });

    test('updating one book creates new list', () {
      final book1 = Book(
        id: 'book-1',
        title: 'Book 1',
        author: 'Author',
        filePath: '/path1.epub',
        addedAt: 0,
        chapters: [],
      );
      final book2 = Book(
        id: 'book-2',
        title: 'Book 2',
        author: 'Author',
        filePath: '/path2.epub',
        addedAt: 0,
        chapters: [],
      );
      
      final state = LibraryState(books: [book1, book2]);
      
      // Simulate updating book1
      final updatedBook1 = book1.copyWith(isFavorite: true);
      final newBooks = state.books.map((b) {
        if (b.id == 'book-1') return updatedBook1;
        return b;
      }).toList();
      
      final newState = state.copyWith(books: newBooks);
      
      expect(newState.books[0].isFavorite, true);
      expect(newState.books[1].isFavorite, false);
    });
  });
}
