import 'package:core_domain/core_domain.dart';

/// The complete view state for playback navigation.
///
/// This sealed hierarchy ensures impossible states cannot occur.
/// All UI decisions are derived from the current state type and its fields.
sealed class PlaybackViewState {
  const PlaybackViewState();
}

/// No active playback. User is browsing the app without audio loaded.
///
/// UI Characteristics:
/// - No mini player anywhere in app
/// - No playback controls
/// - "Start Listening" available on book details
class IdleState extends PlaybackViewState {
  const IdleState();
}

/// Transitioning to new content. Audio is being prepared.
///
/// UI Characteristics:
/// - Loading indicator shown
/// - Previous audio (if any) continues until load completes
/// - User can cancel (back navigation)
class LoadingState extends PlaybackViewState {
  final String bookId;
  final int chapterIndex;
  final int? segmentIndex;

  /// Previous state for cancel/back navigation recovery
  final PlaybackViewState? previousState;

  const LoadingState({
    required this.bookId,
    required this.chapterIndex,
    this.segmentIndex,
    this.previousState,
  });
}

/// User is viewing and controlling the currently playing (or paused) audio.
///
/// UI Characteristics:
/// - Full playback controls (play/pause, skip, speed, sleep timer)
/// - Segment seek slider
/// - Auto-scroll follows audio (when enabled)
/// - "Jump to Audio" button (when auto-scroll disabled by user scroll)
/// - Position auto-saved every 30 seconds
class ActiveState extends PlaybackViewState {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;
  final bool isPlaying;
  final bool autoScrollEnabled;
  final List<Segment> segments;

  /// Book title for display
  final String? bookTitle;

  /// Chapter title for display
  final String? chapterTitle;

  /// Total chapter count for progress display
  final int totalChapters;

  const ActiveState({
    required this.bookId,
    required this.chapterIndex,
    required this.segmentIndex,
    required this.isPlaying,
    required this.autoScrollEnabled,
    required this.segments,
    this.bookTitle,
    this.chapterTitle,
    this.totalChapters = 0,
  });

  ActiveState copyWith({
    int? segmentIndex,
    bool? isPlaying,
    bool? autoScrollEnabled,
    List<Segment>? segments,
    String? bookTitle,
    String? chapterTitle,
    int? totalChapters,
  }) =>
      ActiveState(
        bookId: bookId,
        chapterIndex: chapterIndex,
        segmentIndex: segmentIndex ?? this.segmentIndex,
        isPlaying: isPlaying ?? this.isPlaying,
        autoScrollEnabled: autoScrollEnabled ?? this.autoScrollEnabled,
        segments: segments ?? this.segments,
        bookTitle: bookTitle ?? this.bookTitle,
        chapterTitle: chapterTitle ?? this.chapterTitle,
        totalChapters: totalChapters ?? this.totalChapters,
      );
}

/// User is browsing content different from what's currently playing.
/// Audio continues in background.
///
/// UI Characteristics:
/// - Mini player at bottom (shows what's playing, NOT what's being viewed)
/// - Text display shows viewed chapter (tappable to commit)
/// - No full playback controls (only mini player has play/pause)
/// - No auto-scroll (user is browsing, not following audio)
/// - NO "Jump to Audio" button (use mini player instead)
/// - Position NOT auto-saved (just browsing)
class PreviewState extends PlaybackViewState {
  // What user is viewing
  final String viewingBookId;
  final int viewingChapterIndex;
  final List<Segment> viewingSegments;
  final bool isLoadingPreview;

  /// Viewing book title for display
  final String? viewingBookTitle;

  /// Viewing chapter title for display
  final String? viewingChapterTitle;

  /// Total chapters in viewing book
  final int viewingTotalChapters;

  // What is actually playing
  final String playingBookId;
  final int playingChapterIndex;
  final int playingSegmentIndex;
  final bool isPlaying;

  /// Playing book title for mini player
  final String? playingBookTitle;

  /// Playing chapter title for mini player
  final String? playingChapterTitle;

  const PreviewState({
    required this.viewingBookId,
    required this.viewingChapterIndex,
    required this.viewingSegments,
    this.isLoadingPreview = false,
    this.viewingBookTitle,
    this.viewingChapterTitle,
    this.viewingTotalChapters = 0,
    required this.playingBookId,
    required this.playingChapterIndex,
    required this.playingSegmentIndex,
    required this.isPlaying,
    this.playingBookTitle,
    this.playingChapterTitle,
  });

  /// Same book but different chapter?
  bool get isSameBookPreview => viewingBookId == playingBookId;

  /// Cross-book preview?
  bool get isCrossBookPreview => viewingBookId != playingBookId;

  PreviewState copyWith({
    String? viewingBookId,
    int? viewingChapterIndex,
    List<Segment>? viewingSegments,
    bool? isLoadingPreview,
    String? viewingBookTitle,
    String? viewingChapterTitle,
    int? viewingTotalChapters,
    String? playingBookId,
    int? playingChapterIndex,
    int? playingSegmentIndex,
    bool? isPlaying,
    String? playingBookTitle,
    String? playingChapterTitle,
  }) =>
      PreviewState(
        viewingBookId: viewingBookId ?? this.viewingBookId,
        viewingChapterIndex: viewingChapterIndex ?? this.viewingChapterIndex,
        viewingSegments: viewingSegments ?? this.viewingSegments,
        isLoadingPreview: isLoadingPreview ?? this.isLoadingPreview,
        viewingBookTitle: viewingBookTitle ?? this.viewingBookTitle,
        viewingChapterTitle: viewingChapterTitle ?? this.viewingChapterTitle,
        viewingTotalChapters: viewingTotalChapters ?? this.viewingTotalChapters,
        playingBookId: playingBookId ?? this.playingBookId,
        playingChapterIndex: playingChapterIndex ?? this.playingChapterIndex,
        playingSegmentIndex: playingSegmentIndex ?? this.playingSegmentIndex,
        isPlaying: isPlaying ?? this.isPlaying,
        playingBookTitle: playingBookTitle ?? this.playingBookTitle,
        playingChapterTitle: playingChapterTitle ?? this.playingChapterTitle,
      );
}

/// Extension for UI derivation rules
extension PlaybackViewStateUI on PlaybackViewState {
  /// Whether to show mini player on other screens (library, book details, etc.)
  bool get showMiniPlayerGlobally => switch (this) {
        IdleState() => false,
        LoadingState() => true,
        ActiveState() => true,
        PreviewState() => true,
      };

  /// Whether to show mini player on the playback screen itself
  bool get showMiniPlayerOnPlaybackScreen => switch (this) {
        IdleState() => false,
        LoadingState() => false,
        ActiveState() => false,
        PreviewState() => true,
      };

  /// Whether to show full playback controls
  bool get showFullPlaybackControls => switch (this) {
        IdleState() => false,
        LoadingState() => false,
        ActiveState() => true,
        PreviewState() => false,
      };

  /// Whether to show loading indicator
  bool get showLoadingIndicator => switch (this) {
        IdleState() => false,
        LoadingState() => true,
        ActiveState() => false,
        PreviewState(isLoadingPreview: true) => true,
        PreviewState() => false,
      };

  /// Whether to auto-scroll text
  bool get shouldAutoScroll => switch (this) {
        ActiveState(autoScrollEnabled: true) => true,
        _ => false,
      };

  /// Whether to show "Jump to Audio" button
  bool get showJumpToAudioButton => switch (this) {
        ActiveState(autoScrollEnabled: false) => true,
        _ => false,
      };

  /// Whether to auto-save position periodically
  bool get shouldAutoSavePosition => switch (this) {
        ActiveState() => true,
        _ => false,
      };

  /// Whether segment tap should seek (Active) or commit (Preview)
  bool get segmentTapSeeks => switch (this) {
        ActiveState() => true,
        _ => false,
      };

  /// Get the currently playing book ID (if any)
  String? get playingBookId => switch (this) {
        IdleState() => null,
        LoadingState(bookId: final id) => id,
        ActiveState(bookId: final id) => id,
        PreviewState(playingBookId: final id) => id,
      };

  /// Get the book ID being viewed (for display)
  String? get viewingBookId => switch (this) {
        IdleState() => null,
        LoadingState(bookId: final id) => id,
        ActiveState(bookId: final id) => id,
        PreviewState(viewingBookId: final id) => id,
      };

  /// Whether there is active playback (playing or paused)
  bool get hasActivePlayback => switch (this) {
        IdleState() => false,
        LoadingState() => false,
        ActiveState() => true,
        PreviewState() => true,
      };

  /// Current playing state
  bool get isPlaying => switch (this) {
        ActiveState(isPlaying: final playing) => playing,
        PreviewState(isPlaying: final playing) => playing,
        _ => false,
      };
}
