/// Unified chapter navigation service.
///
/// This service is the SINGLE ENTRY POINT for all chapter navigation:
/// - Manual navigation (user taps chapter)
/// - Auto-advance (chapter ends, auto-play next)
/// - Snap-back (return from browsing mode)
/// - Deep links (navigate to specific chapter/segment)
///
/// ## Why This Exists
///
/// Previously, navigation was scattered across:
/// - PlaybackScreen._jumpToChapter()
/// - PlaybackScreen._autoAdvanceToNextChapter()
/// - ListeningActionsNotifier.jumpToChapter()
/// - Direct calls to playbackControllerProvider.loadChapter()
///
/// This led to:
/// - Inconsistent browsing mode handling
/// - Position saves happening in some paths but not others
/// - Duplicated logic for determining resume positions
///
/// ## Usage
///
/// ```dart
/// final service = await ref.read(chapterNavigationServiceProvider.future);
///
/// // User manually selects a chapter
/// await service.navigateToChapter(
///   book: book,
///   targetChapter: 5,
///   source: NavigationSource.userManual,
/// );
///
/// // Auto-advance to next chapter
/// await service.navigateToChapter(
///   book: book,
///   targetChapter: currentChapter + 1,
///   source: NavigationSource.autoAdvance,
/// );
///
/// // Return to primary position (snap-back)
/// await service.snapBack(book: book);
/// ```
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback_providers.dart';
import 'playback_position_service.dart';

/// Source of a navigation action.
///
/// This affects how position and browsing mode are handled.
enum NavigationSource {
  /// User manually selected a chapter (tapped in list).
  /// - Enters browsing mode if navigating away from primary
  /// - Saves current position before jumping
  userManual,

  /// Auto-advance when chapter ends.
  /// - Does NOT enter browsing mode
  /// - Updates primary position to new chapter
  autoAdvance,

  /// Initial load when entering playback screen.
  /// - Does NOT enter browsing mode
  /// - Uses existing primary position
  initialLoad,

  /// Deep link or query param navigation.
  /// - Does NOT enter browsing mode (user explicitly requested this position)
  /// - Updates primary position
  deepLink,

  /// Snap-back to primary position.
  /// - Exits browsing mode
  /// - Uses primary position
  snapBack,
}

/// Result of a navigation action.
class NavigationResult {
  /// Whether navigation succeeded.
  final bool success;

  /// Error message if navigation failed.
  final String? error;

  /// The chapter navigated to.
  final int? chapterIndex;

  /// The segment navigated to.
  final int? segmentIndex;

  /// Whether browsing mode is now active.
  final bool isBrowsing;

  const NavigationResult({
    required this.success,
    this.error,
    this.chapterIndex,
    this.segmentIndex,
    this.isBrowsing = false,
  });

  factory NavigationResult.success({
    required int chapterIndex,
    required int segmentIndex,
    bool isBrowsing = false,
  }) {
    return NavigationResult(
      success: true,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      isBrowsing: isBrowsing,
    );
  }

  factory NavigationResult.failure(String error) {
    return NavigationResult(success: false, error: error);
  }

  @override
  String toString() {
    if (success) {
      return 'NavigationResult.success(chapter: $chapterIndex, segment: $segmentIndex, browsing: $isBrowsing)';
    }
    return 'NavigationResult.failure($error)';
  }
}

/// Service for unified chapter navigation.
///
/// All navigation goes through this service to ensure consistent
/// position tracking, browsing mode handling, and state updates.
class ChapterNavigationService {
  final Ref _ref;
  final PlaybackPositionService _positionService;

  ChapterNavigationService(this._ref, this._positionService);

  /// Navigate to a chapter.
  ///
  /// This is the SINGLE ENTRY POINT for all chapter navigation.
  /// The [source] determines how position and browsing mode are handled.
  ///
  /// [targetSegment] - Specific segment to start at, or null to use saved position.
  /// [autoPlay] - Whether to start playing immediately.
  Future<NavigationResult> navigateToChapter({
    required Book book,
    required int targetChapter,
    required NavigationSource source,
    int? targetSegment,
    bool autoPlay = true,
  }) async {
    developer.log(
      '[ChapterNavigationService] navigateToChapter: '
      'book=${book.id}, chapter=$targetChapter, source=$source',
    );

    // Validate chapter index
    if (targetChapter < 0 || targetChapter >= book.chapters.length) {
      return NavigationResult.failure(
        'Invalid chapter index: $targetChapter (book has ${book.chapters.length} chapters)',
      );
    }

    try {
      // Get current position before navigation
      final currentPosition =
          await _positionService.getPrimaryPosition(book.id);
      final currentChapter = currentPosition?.chapterIndex ?? 0;
      final currentSegment = currentPosition?.segmentIndex ?? 0;

      // Determine segment to start at
      int startSegment;
      if (targetSegment != null) {
        startSegment = targetSegment;
      } else {
        // Use saved position for this chapter
        startSegment =
            await _positionService.getChapterResumeSegment(book.id, targetChapter);
      }

      // Handle browsing mode based on source
      bool enterBrowsing = false;
      bool updatePrimary = true;

      switch (source) {
        case NavigationSource.userManual:
          // User manually jumping - this may enter browsing mode
          if (currentPosition != null && targetChapter != currentChapter) {
            enterBrowsing = true;
            updatePrimary = false; // Preserve snap-back target
            developer.log(
              '[ChapterNavigationService] Entering browsing mode: '
              'from chapter $currentChapter to $targetChapter',
            );
          }
          // Save current position before jumping
          if (currentPosition != null) {
            await _positionService.updatePosition(
              bookId: book.id,
              chapterIndex: currentChapter,
              segmentIndex: currentSegment,
              updatePrimary: true, // This becomes the snap-back target
            );
          }

        case NavigationSource.autoAdvance:
          // Auto-advance - normal progression, update primary
          updatePrimary = true;
          enterBrowsing = false;

        case NavigationSource.initialLoad:
          // Initial load - just use what's there
          updatePrimary = false;
          enterBrowsing = false;

        case NavigationSource.deepLink:
          // Deep link - user explicitly requested this position
          updatePrimary = true;
          enterBrowsing = false;

        case NavigationSource.snapBack:
          // Snap-back - return to primary, exit browsing
          updatePrimary = false; // Primary is already correct
          enterBrowsing = false;
      }

      // Update browsing mode state
      if (enterBrowsing) {
        _ref.read(browsingModeNotifierProvider.notifier).enterBrowsingMode(book.id);
      } else if (source == NavigationSource.snapBack) {
        _ref.read(browsingModeNotifierProvider.notifier).exitBrowsingMode(book.id);
      }

      // Load the chapter via playback controller
      final controller = _ref.read(playbackControllerProvider.notifier);
      await controller.loadChapter(
        book: book,
        chapterIndex: targetChapter,
        startSegmentIndex: startSegment,
        autoPlay: autoPlay,
      );

      // Save position if needed
      if (updatePrimary) {
        await _positionService.updatePosition(
          bookId: book.id,
          chapterIndex: targetChapter,
          segmentIndex: startSegment,
          updatePrimary: true,
        );
      }

      // Invalidate position providers to refresh UI
      _ref.invalidate(resumePositionProvider(book.id));
      _ref.invalidate(primaryPositionServiceProvider(book.id));
      _ref.invalidate(allPositionsProvider(book.id));

      final isBrowsing =
          _ref.read(browsingModeNotifierProvider.notifier).isBrowsing(book.id);

      developer.log(
        '[ChapterNavigationService] Navigation complete: '
        'chapter=$targetChapter, segment=$startSegment, browsing=$isBrowsing',
      );

      return NavigationResult.success(
        chapterIndex: targetChapter,
        segmentIndex: startSegment,
        isBrowsing: isBrowsing,
      );
    } catch (e, st) {
      developer.log('[ChapterNavigationService] Navigation failed: $e');
      developer.log('[ChapterNavigationService] Stack trace: $st');
      return NavigationResult.failure(e.toString());
    }
  }

  /// Navigate to the next chapter.
  ///
  /// Convenience method for auto-advance or user pressing "next".
  Future<NavigationResult> nextChapter({
    required Book book,
    required int currentChapter,
    required NavigationSource source,
    bool autoPlay = true,
  }) async {
    final nextChapter = currentChapter + 1;
    if (nextChapter >= book.chapters.length) {
      return NavigationResult.failure('Already at last chapter');
    }

    return navigateToChapter(
      book: book,
      targetChapter: nextChapter,
      source: source,
      targetSegment: 0, // Always start at beginning for next chapter
      autoPlay: autoPlay,
    );
  }

  /// Navigate to the previous chapter.
  Future<NavigationResult> previousChapter({
    required Book book,
    required int currentChapter,
    required NavigationSource source,
    bool autoPlay = true,
  }) async {
    final prevChapter = currentChapter - 1;
    if (prevChapter < 0) {
      return NavigationResult.failure('Already at first chapter');
    }

    return navigateToChapter(
      book: book,
      targetChapter: prevChapter,
      source: source,
      autoPlay: autoPlay,
    );
  }

  /// Snap back to the primary position.
  ///
  /// Used when user clicks "Back to Chapter X" in browsing mode.
  Future<NavigationResult> snapBack({required Book book}) async {
    final primaryPosition = await _positionService.getPrimaryPosition(book.id);
    if (primaryPosition == null) {
      return NavigationResult.failure('No primary position to snap back to');
    }

    developer.log(
      '[ChapterNavigationService] Snapping back to chapter ${primaryPosition.chapterIndex}',
    );

    return navigateToChapter(
      book: book,
      targetChapter: primaryPosition.chapterIndex,
      source: NavigationSource.snapBack,
      targetSegment: primaryPosition.segmentIndex,
      autoPlay: true,
    );
  }

  /// Promote current position to primary (exit browsing mode).
  ///
  /// Called after 30 seconds of listening in a browsed chapter.
  Future<void> promoteToPrimary({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
  }) async {
    developer.log(
      '[ChapterNavigationService] Promoting chapter $chapterIndex to primary',
    );

    await _positionService.updatePosition(
      bookId: bookId,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      updatePrimary: true,
    );

    _ref.read(browsingModeNotifierProvider.notifier).exitBrowsingMode(bookId);

    // Invalidate providers
    _ref.invalidate(resumePositionProvider(bookId));
    _ref.invalidate(primaryPositionServiceProvider(bookId));
    _ref.invalidate(allPositionsProvider(bookId));
  }

  /// Get the initial position for entering playback.
  ///
  /// Used by PlaybackScreen to determine where to start.
  Future<PlaybackPosition> getInitialPosition({
    required String bookId,
    int? overrideChapter,
    int? overrideSegment,
  }) async {
    // If explicit position provided (deep link), use that
    if (overrideChapter != null) {
      return PlaybackPosition(
        bookId: bookId,
        chapterIndex: overrideChapter,
        segmentIndex: overrideSegment ?? 0,
        isPrimary: true,
        updatedAt: DateTime.now(),
      );
    }

    // Otherwise use saved position
    return _positionService.getResumePosition(bookId);
  }
}

/// Provider for ChapterNavigationService.
final chapterNavigationServiceProvider =
    FutureProvider<ChapterNavigationService>((ref) async {
  final positionService =
      await ref.watch(playbackPositionServiceFutureProvider.future);

  return ChapterNavigationService(ref, positionService);
});
