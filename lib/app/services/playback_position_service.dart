/// Single source of truth for playback position tracking.
///
/// This service consolidates all position tracking into ONE system:
/// - Uses `chapter_positions` table exclusively (deprecated reading_progress for position)
/// - Provides primary position (snap-back target)
/// - Provides per-chapter resume positions
/// - Handles auto-save timer internally
///
/// ## Why This Exists
///
/// Previously, position was tracked in multiple places:
/// - Book.progress (in-memory)
/// - reading_progress table (SQLite)
/// - chapter_positions table (SQLite)
/// - _currentChapterIndex in PlaybackScreen (widget state)
///
/// This led to:
/// - Inconsistent resume behavior
/// - Lost progress on crashes
/// - Duplicated save logic scattered across files
///
/// ## Usage
///
/// ```dart
/// // Get resume position when loading playback
/// final position = await ref.read(playbackPositionServiceProvider)
///     .getResumePosition(bookId);
///
/// // Auto-save is handled internally when you call updatePosition
/// await service.updatePosition(bookId, chapterIndex, segmentIndex);
/// ```
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/chapter_position_dao.dart';
import '../database/app_database.dart';
import '../library_controller.dart';

/// Represents the current playback position.
class PlaybackPosition {
  /// The book ID this position is for.
  final String bookId;

  /// The chapter index (0-based).
  final int chapterIndex;

  /// The segment index within the chapter (0-based).
  final int segmentIndex;

  /// Whether this is the primary position (snap-back target).
  final bool isPrimary;

  /// When this position was last updated.
  final DateTime updatedAt;

  const PlaybackPosition({
    required this.bookId,
    required this.chapterIndex,
    required this.segmentIndex,
    required this.isPrimary,
    required this.updatedAt,
  });

  /// Create from ChapterPosition (internal DAO type).
  factory PlaybackPosition.fromChapterPosition(
    String bookId,
    ChapterPosition pos,
  ) {
    return PlaybackPosition(
      bookId: bookId,
      chapterIndex: pos.chapterIndex,
      segmentIndex: pos.segmentIndex,
      isPrimary: pos.isPrimary,
      updatedAt: pos.updatedAt,
    );
  }

  /// Default position at the start of the book.
  factory PlaybackPosition.start(String bookId) {
    return PlaybackPosition(
      bookId: bookId,
      chapterIndex: 0,
      segmentIndex: 0,
      isPrimary: true,
      updatedAt: DateTime.now(),
    );
  }

  PlaybackPosition copyWith({
    String? bookId,
    int? chapterIndex,
    int? segmentIndex,
    bool? isPrimary,
    DateTime? updatedAt,
  }) {
    return PlaybackPosition(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      isPrimary: isPrimary ?? this.isPrimary,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'PlaybackPosition(book: $bookId, chapter: $chapterIndex, segment: $segmentIndex, primary: $isPrimary)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackPosition &&
        other.bookId == bookId &&
        other.chapterIndex == chapterIndex &&
        other.segmentIndex == segmentIndex &&
        other.isPrimary == isPrimary;
  }

  @override
  int get hashCode =>
      Object.hash(bookId, chapterIndex, segmentIndex, isPrimary);
}

/// Service for managing playback position persistence.
///
/// This is the SINGLE SOURCE OF TRUTH for position tracking.
/// All other position-related code should use this service.
class PlaybackPositionService {
  final ChapterPositionDao _dao;
  final Ref _ref;

  /// Auto-save timer for the current book.
  Timer? _autoSaveTimer;
  String? _currentBookId;
  int _lastSavedChapter = -1;
  int _lastSavedSegment = -1;

  static const _autoSaveInterval = Duration(seconds: 30);

  PlaybackPositionService(this._dao, this._ref);

  /// Get the primary position for a book (where user was actively listening).
  ///
  /// This is the snap-back target when returning from browsing mode.
  /// Returns null if no position has been saved yet.
  Future<PlaybackPosition?> getPrimaryPosition(String bookId) async {
    final pos = await _dao.getPrimaryPosition(bookId);
    if (pos == null) return null;
    return PlaybackPosition.fromChapterPosition(bookId, pos);
  }

  /// Get the resume position for a book.
  ///
  /// Returns the primary position if one exists, otherwise starts at beginning.
  /// This is the main entry point for "Continue Reading" functionality.
  Future<PlaybackPosition> getResumePosition(String bookId) async {
    final primary = await getPrimaryPosition(bookId);
    return primary ?? PlaybackPosition.start(bookId);
  }

  /// Get the resume position for a specific chapter.
  ///
  /// Returns the saved segment index for that chapter, or 0 if none saved.
  /// Used when navigating to a chapter (not starting the book).
  Future<int> getChapterResumeSegment(String bookId, int chapterIndex) async {
    final pos = await _dao.getChapterPosition(bookId, chapterIndex);
    return pos?.segmentIndex ?? 0;
  }

  /// Update the current playback position.
  ///
  /// This saves to chapter_positions and optionally updates the primary flag.
  /// Call this when:
  /// - User manually navigates to a position
  /// - Auto-save timer fires (internal)
  /// - Playback stops (pause, exit)
  ///
  /// If [updatePrimary] is true, this position becomes the snap-back target.
  /// Default is true for normal playback; set to false for browsing mode.
  Future<void> updatePosition({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
    bool updatePrimary = true,
  }) async {
    // Skip redundant saves
    if (bookId == _currentBookId &&
        chapterIndex == _lastSavedChapter &&
        segmentIndex == _lastSavedSegment) {
      return;
    }

    if (updatePrimary) {
      // Clear existing primary flag before setting new one
      await _dao.clearPrimaryFlag(bookId);
    }

    await _dao.savePosition(
      bookId: bookId,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
      isPrimary: updatePrimary,
    );

    _lastSavedChapter = chapterIndex;
    _lastSavedSegment = segmentIndex;

    // Also update Book.progress for UI (library shelf display)
    // This is the ONLY place that updates in-memory progress
    _ref.read(libraryProvider.notifier).updateProgress(
          bookId,
          chapterIndex,
          segmentIndex,
        );

    developer.log(
      '[PlaybackPositionService] Saved position: chapter $chapterIndex, segment $segmentIndex (primary: $updatePrimary)',
    );
  }

  /// Start auto-save timer for a book.
  ///
  /// Call this when playback starts. Auto-save will run every 30 seconds.
  /// The actual position is read from the provided callback.
  void startAutoSave({
    required String bookId,
    required int Function() getChapterIndex,
    required int Function() getSegmentIndex,
  }) {
    stopAutoSave();
    _currentBookId = bookId;

    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      final chapter = getChapterIndex();
      final segment = getSegmentIndex();
      updatePosition(
        bookId: bookId,
        chapterIndex: chapter,
        segmentIndex: segment,
      );
    });

    developer.log('[PlaybackPositionService] Auto-save started for book $bookId');
  }

  /// Stop auto-save timer.
  ///
  /// Call this when playback stops or screen is disposed.
  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _currentBookId = null;
    developer.log('[PlaybackPositionService] Auto-save stopped');
  }

  /// Save the current position immediately.
  ///
  /// Call this when:
  /// - User pauses
  /// - User exits playback screen
  /// - App goes to background
  Future<void> saveNow({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
  }) async {
    await updatePosition(
      bookId: bookId,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
    );
  }

  /// Get all saved positions for a book.
  ///
  /// Returns a map of chapterIndex -> PlaybackPosition.
  /// Used for showing position indicators in chapter list UI.
  Future<Map<int, PlaybackPosition>> getAllPositions(String bookId) async {
    final positions = await _dao.getAllPositions(bookId);
    return {
      for (final entry in positions.entries)
        entry.key: PlaybackPosition.fromChapterPosition(bookId, entry.value)
    };
  }

  /// Set a chapter as the primary position without updating its segment.
  ///
  /// Used when user commits to a browsed chapter (30s auto-promotion).
  Future<void> promoteToPrimary(String bookId, int chapterIndex) async {
    await _dao.setPrimaryChapter(bookId, chapterIndex);
    developer.log(
      '[PlaybackPositionService] Promoted chapter $chapterIndex to primary',
    );
  }

  /// Clear all position data for a book.
  ///
  /// Call this when a book is deleted.
  Future<void> clearBookPositions(String bookId) async {
    await _dao.deleteBookPositions(bookId);
    developer.log('[PlaybackPositionService] Cleared positions for book $bookId');
  }

  /// Dispose of resources.
  void dispose() {
    stopAutoSave();
  }
}

/// Provider for the PlaybackPositionService.
final playbackPositionServiceProvider = Provider<PlaybackPositionService>((ref) {
  // We need to create the DAO synchronously, so we use a FutureProvider helper
  throw UnimplementedError(
    'Use playbackPositionServiceFutureProvider instead for async initialization',
  );
});

/// Async provider for PlaybackPositionService.
///
/// Use this when you need the service in async contexts.
final playbackPositionServiceFutureProvider =
    FutureProvider<PlaybackPositionService>((ref) async {
  final db = await AppDatabase.instance;
  final dao = ChapterPositionDao(db);
  final service = PlaybackPositionService(dao, ref);

  ref.onDispose(() => service.dispose());

  return service;
});

/// Provider for the current resume position of a book.
///
/// Invalidate this provider when position changes to refresh UI.
/// Parameter: bookId
final resumePositionProvider =
    FutureProvider.family<PlaybackPosition, String>((ref, bookId) async {
  final service = await ref.watch(playbackPositionServiceFutureProvider.future);
  return service.getResumePosition(bookId);
});

/// Provider for the primary position of a book (snap-back target).
///
/// Parameter: bookId
final primaryPositionServiceProvider =
    FutureProvider.family<PlaybackPosition?, String>((ref, bookId) async {
  final service = await ref.watch(playbackPositionServiceFutureProvider.future);
  return service.getPrimaryPosition(bookId);
});

/// Provider for all positions of a book.
///
/// Returns a map of chapterIndex -> PlaybackPosition.
/// Parameter: bookId
final allPositionsProvider =
    FutureProvider.family<Map<int, PlaybackPosition>, String>(
        (ref, bookId) async {
  final service = await ref.watch(playbackPositionServiceFutureProvider.future);
  return service.getAllPositions(bookId);
});
