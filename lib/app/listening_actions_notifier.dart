import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_providers.dart';

/// Notifier for managing listening position.
///
/// Handles the logic for:
/// - Saving the last played position
/// - Allowing navigation between chapters
/// - Returning to the last played position
class ListeningActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Jump to a chapter, saving current position.
  ///
  /// When jumping from one chapter to another:
  /// 1. Saves the current position as the last played position
  /// 2. Navigates to the target chapter's saved position (or segment 0)
  ///
  /// Returns the segment index to start at in the target chapter.
  Future<int> jumpToChapter({
    required String bookId,
    required int currentChapter,
    required int currentSegment,
    required int targetChapter,
  }) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);

    // Save current position as the last played position
    await dao.clearPrimaryFlag(bookId);
    await dao.savePosition(
      bookId: bookId,
      chapterIndex: currentChapter,
      segmentIndex: currentSegment,
      isPrimary: true,
    );

    // Check for existing position in target chapter
    final targetPosition = await dao.getChapterPosition(bookId, targetChapter);
    final targetSegment = targetPosition?.segmentIndex ?? 0;

    // Invalidate providers to reflect changes
    ref.invalidate(chapterPositionsProvider(bookId));
    ref.invalidate(primaryPositionProvider(bookId));

    return targetSegment;
  }

  /// Return to the last played position.
  ///
  /// Returns the (chapterIndex, segmentIndex) to navigate to,
  /// or null if there's no saved position to return to.
  Future<({int chapterIndex, int segmentIndex})?> returnToLastPlayed(
    String bookId,
  ) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);
    final lastPlayed = await dao.getPrimaryPosition(bookId);

    if (lastPlayed == null) return null;

    return (chapterIndex: lastPlayed.chapterIndex, segmentIndex: lastPlayed.segmentIndex);
  }

  /// Save the current playback position.
  ///
  /// Used for periodic auto-save during playback.
  /// Always saves the current position as the last played position.
  Future<void> saveCurrentPosition({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
  }) async {
    final dao = await ref.read(chapterPositionDaoProvider.future);

    // Always save as the primary (last played) position
    await dao.savePosition(
      bookId: bookId,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      isPrimary: true,
    );

    // Invalidate providers
    ref.invalidate(chapterPositionsProvider(bookId));
    ref.invalidate(primaryPositionProvider(bookId));
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

}

/// Provider for listening actions (chapter navigation, browsing mode).
final listeningActionsProvider = NotifierProvider<ListeningActionsNotifier, void>(
  ListeningActionsNotifier.new,
);
