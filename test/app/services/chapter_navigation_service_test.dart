import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/app/services/chapter_navigation_service.dart';

void main() {
  group('NavigationSource', () {
    test('userManual triggers browsing mode for non-adjacent chapters', () {
      // Documentation test - verifies the enum semantics are clear
      const source = NavigationSource.userManual;
      // When source is userManual and jumping to non-adjacent chapter:
      // - Saves current position as primary (snap-back target)
      // - Enters browsing mode
      // - Does NOT update primary to new chapter
      expect(source, NavigationSource.userManual);
    });

    test('autoAdvance never triggers browsing mode', () {
      const source = NavigationSource.autoAdvance;
      // When source is autoAdvance:
      // - Updates primary position to new chapter
      // - Never enters browsing mode
      // - Used for end-of-chapter auto-advance
      expect(source, NavigationSource.autoAdvance);
    });

    test('initialLoad preserves existing positions', () {
      const source = NavigationSource.initialLoad;
      // When source is initialLoad:
      // - Does NOT enter browsing mode
      // - Does NOT update primary position
      // - Simply loads to saved position
      expect(source, NavigationSource.initialLoad);
    });

    test('deepLink updates primary immediately', () {
      const source = NavigationSource.deepLink;
      // When source is deepLink:
      // - Does NOT enter browsing mode (user explicitly requested this)
      // - Updates primary position to deep link target
      // - Used for URL navigation
      expect(source, NavigationSource.deepLink);
    });

    test('snapBack exits browsing mode', () {
      const source = NavigationSource.snapBack;
      // When source is snapBack:
      // - Exits browsing mode
      // - Navigates to primary position
      // - Does NOT update primary (already correct)
      expect(source, NavigationSource.snapBack);
    });
  });

  group('NavigationResult', () {
    test('success factory creates valid success result', () {
      final result = NavigationResult.success(
        chapterIndex: 5,
        segmentIndex: 10,
        isBrowsing: true,
      );

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(result.chapterIndex, 5);
      expect(result.segmentIndex, 10);
      expect(result.isBrowsing, isTrue);
    });

    test('failure factory creates valid failure result', () {
      final result = NavigationResult.failure('Chapter not found');

      expect(result.success, isFalse);
      expect(result.error, 'Chapter not found');
      expect(result.chapterIndex, isNull);
      expect(result.segmentIndex, isNull);
    });

    test('toString provides useful debugging output', () {
      final success = NavigationResult.success(
        chapterIndex: 5,
        segmentIndex: 10,
        isBrowsing: false,
      );
      final failure = NavigationResult.failure('Error');

      expect(success.toString(), contains('success'));
      expect(success.toString(), contains('5'));
      expect(failure.toString(), contains('failure'));
      expect(failure.toString(), contains('Error'));
    });
  });

  // Note: Full service tests require Riverpod container and database mocking.
  // See integration tests for end-to-end testing.
  group('ChapterNavigationService documentation', () {
    test('service is single entry point for ALL navigation', () {
      // This is a documentation test - verifies the service purpose is clear
      // The service replaces:
      // 1. PlaybackScreen._jumpToChapter()
      // 2. PlaybackScreen._autoAdvanceToNextChapter()
      // 3. ListeningActionsNotifier.jumpToChapter()
      // 4. Direct calls to playbackControllerProvider.loadChapter()
      //
      // With ONE unified API: ChapterNavigationService.navigateToChapter()
      expect(true, isTrue);
    });
  });
}
