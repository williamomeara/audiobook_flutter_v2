import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_providers.dart';

/// Notifier for managing listening position and browsing mode.
///
/// Handles the logic for:
/// - Saving positions before chapter jumps
/// - Entering/exiting browsing mode
/// - Snap-back to primary position
/// - Auto-promotion after listening duration
class ListeningActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Jump to a chapter, saving current position and entering browsing mode.
  ///
  /// When jumping from one chapter to another:
  /// 1. Saves the current position
  /// 2. If this is the first jump (not already browsing), marks current as primary
  /// 3. Enters browsing mode
  /// 4. Navigates to the target chapter's saved position (or segment 0)
  ///
  /// Returns the segment index to start at in the target chapter.
  Future<int> jumpToChapter({
    required String bookId,
    required int currentChapter,
    required int currentSegment,
    required int targetChapter,
  }) async {
    final isBrowsing = ref.read(isBrowsingProvider(bookId));
    final dao = await ref.read(chapterPositionDaoProvider.future);

    if (!isBrowsing) {
      // First jump - save current position as primary
      await dao.clearPrimaryFlag(bookId);
      await dao.savePosition(
        bookId: bookId,
        chapterIndex: currentChapter,
        segmentIndex: currentSegment,
        isPrimary: true,
      );
      // Enter browsing mode
      ref.read(browsingModeNotifierProvider.notifier).enterBrowsingMode(bookId);
    } else {
      // Already browsing - just save current position (not primary)
      await dao.savePosition(
        bookId: bookId,
        chapterIndex: currentChapter,
        segmentIndex: currentSegment,
        isPrimary: false,
      );
    }

    // Check for existing position in target chapter
    final targetPosition = await dao.getChapterPosition(bookId, targetChapter);
    final targetSegment = targetPosition?.segmentIndex ?? 0;

    // Invalidate providers to reflect changes
    ref.invalidate(chapterPositionsProvider(bookId));
    ref.invalidate(primaryPositionProvider(bookId));

    return targetSegment;
  }

  /// Snap back to the primary listening position.
  ///
  /// Returns the (chapterIndex, segmentIndex) to navigate to,
  /// or null if there's no primary position to snap back to.
  Future<({int chapterIndex, int segmentIndex})?> snapBackToPrimary(
    String bookId,
  ) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);
    final primary = await dao.getPrimaryPosition(bookId);

    if (primary == null) return null;

    // Exit browsing mode
    ref.read(browsingModeNotifierProvider.notifier).exitBrowsingMode(bookId);

    return (chapterIndex: primary.chapterIndex, segmentIndex: primary.segmentIndex);
  }

  /// Commit current position as the new primary position.
  ///
  /// Called when:
  /// - User has listened for 30+ seconds in a browsed chapter (auto-promotion)
  /// - User explicitly commits to the new position
  ///
  /// This clears the old primary, sets the new one, and exits browsing mode.
  Future<void> commitCurrentPosition({
    required String bookId,
    required int currentChapter,
    required int currentSegment,
  }) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);

    // Clear old primary flag
    await dao.clearPrimaryFlag(bookId);

    // Set current position as new primary
    await dao.savePosition(
      bookId: bookId,
      chapterIndex: currentChapter,
      segmentIndex: currentSegment,
      isPrimary: true,
    );

    // Exit browsing mode
    ref.read(browsingModeNotifierProvider.notifier).exitBrowsingMode(bookId);

    // Invalidate providers
    ref.invalidate(chapterPositionsProvider(bookId));
    ref.invalidate(primaryPositionProvider(bookId));
  }

  /// Save the current position without changing browsing mode.
  ///
  /// Used for periodic auto-save during playback.
  /// Does not affect primary status or browsing mode.
  Future<void> saveCurrentPosition({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
  }) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);
    final isBrowsing = ref.read(isBrowsingProvider(bookId));

    // When browsing, save as non-primary (preserve the snap-back target)
    // When not browsing, save as primary (this is the main listening position)
    await dao.savePosition(
      bookId: bookId,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      isPrimary: !isBrowsing,
    );

    // Invalidate providers
    ref.invalidate(chapterPositionsProvider(bookId));
    if (!isBrowsing) {
      ref.invalidate(primaryPositionProvider(bookId));
    }
  }

  /// Exit browsing mode without snapping back.
  ///
  /// Used when playback is stopped or the user exits the playback screen
  /// while in browsing mode. The primary position is preserved.
  void exitBrowsingMode(String bookId) {
    ref.read(browsingModeNotifierProvider.notifier).exitBrowsingMode(bookId);
  }

  /// Get the resume position for a chapter.
  ///
  /// Returns the saved segment index for the chapter, or 0 if no position saved.
  /// Used when loading a chapter to determine where to start.
  Future<int> getResumePosition(String bookId, int chapterIndex) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);
    final position = await dao.getChapterPosition(bookId, chapterIndex);
    return position?.segmentIndex ?? 0;
  }

  /// Check if user is browsing away from their primary position.
  ///
  /// Returns true if browsing mode is active AND the current chapter
  /// differs from the primary position.
  bool isBrowsingDifferentChapter(String bookId, int currentChapter) {
    final isBrowsing = ref.read(isBrowsingProvider(bookId));
    if (!isBrowsing) return false;

    final primaryAsync = ref.read(primaryPositionProvider(bookId));
    final primary = primaryAsync.value;
    if (primary == null) return false;

    return primary.chapterIndex != currentChapter;
  }
}

/// Provider for listening actions (chapter navigation, browsing mode).
final listeningActionsProvider = NotifierProvider<ListeningActionsNotifier, void>(
  ListeningActionsNotifier.new,
);
