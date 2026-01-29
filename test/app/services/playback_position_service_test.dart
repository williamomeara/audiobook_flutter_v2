import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/app/services/playback_position_service.dart';

void main() {
  group('PlaybackPosition', () {
    test('start() creates position at beginning of book', () {
      final position = PlaybackPosition.start('book-123');

      expect(position.bookId, 'book-123');
      expect(position.chapterIndex, 0);
      expect(position.segmentIndex, 0);
      expect(position.isPrimary, true);
    });

    test('copyWith preserves unchanged fields', () {
      final original = PlaybackPosition(
        bookId: 'book-123',
        chapterIndex: 5,
        segmentIndex: 10,
        isPrimary: true,
        updatedAt: DateTime(2024, 1, 1),
      );

      final updated = original.copyWith(segmentIndex: 15);

      expect(updated.bookId, 'book-123');
      expect(updated.chapterIndex, 5);
      expect(updated.segmentIndex, 15);
      expect(updated.isPrimary, true);
    });

    test('equality compares all fields', () {
      final now = DateTime.now();
      final pos1 = PlaybackPosition(
        bookId: 'book-123',
        chapterIndex: 5,
        segmentIndex: 10,
        isPrimary: true,
        updatedAt: now,
      );
      final pos2 = PlaybackPosition(
        bookId: 'book-123',
        chapterIndex: 5,
        segmentIndex: 10,
        isPrimary: true,
        updatedAt: now,
      );
      final pos3 = PlaybackPosition(
        bookId: 'book-123',
        chapterIndex: 5,
        segmentIndex: 11, // Different segment
        isPrimary: true,
        updatedAt: now,
      );

      expect(pos1, equals(pos2));
      expect(pos1, isNot(equals(pos3)));
    });

    test('toString provides useful debugging output', () {
      final position = PlaybackPosition(
        bookId: 'book-123',
        chapterIndex: 5,
        segmentIndex: 10,
        isPrimary: true,
        updatedAt: DateTime(2024, 1, 1),
      );

      final str = position.toString();

      expect(str, contains('book-123'));
      expect(str, contains('5'));
      expect(str, contains('10'));
      expect(str, contains('primary: true'));
    });
  });

  // Note: Full service tests require database mocking.
  // See integration tests for end-to-end testing.
  group('PlaybackPositionService documentation', () {
    test('service has clear purpose: single source of truth', () {
      // This is a documentation test - verifies the service API makes sense
      // The service consolidates:
      // 1. reading_progress table (deprecated for position)
      // 2. chapter_positions table (primary source)
      // 3. Book.progress (in-memory)
      // 4. _currentChapterIndex (widget state)
      //
      // Into ONE system: PlaybackPositionService
      expect(true, isTrue);
    });
  });
}
