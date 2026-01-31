import 'package:audiobook_flutter_v2/app/playback/state/playback_event.dart';
import 'package:audiobook_flutter_v2/app/playback/state/playback_side_effect.dart';
import 'package:audiobook_flutter_v2/app/playback/state/playback_view_state.dart';

/// Result of a state transition: new state plus side effects to execute
typedef TransitionResult = (PlaybackViewState, List<PlaybackSideEffect>);

/// Pure function: given current state and event, compute next state and side effects.
/// Side effects (loading, playing, saving) are handled separately by listeners.
TransitionResult transition(PlaybackViewState state, PlaybackEvent event) {
  return switch ((state, event)) {
    // =========================================================================
    // From Idle
    // =========================================================================
    (IdleState(), StartListeningPressed e) => (
        LoadingState(
          bookId: e.bookId,
          chapterIndex: e.chapterIndex,
          segmentIndex: e.segmentIndex,
          previousState: const IdleState(),
        ),
        [
          LoadChapter(e.bookId, e.chapterIndex,
              segmentIndex: e.segmentIndex, autoPlay: true)
        ],
      ),

    (IdleState(), ChapterSelected e) => (
        LoadingState(
          bookId: e.bookId,
          chapterIndex: e.chapterIndex,
          previousState: const IdleState(),
        ),
        [LoadChapter(e.bookId, e.chapterIndex, autoPlay: true)],
      ),

    (IdleState(), RestorePlayback e) => (
        LoadingState(
          bookId: e.bookId,
          chapterIndex: e.chapterIndex,
          segmentIndex: e.segmentIndex,
          previousState: const IdleState(),
        ),
        [
          LoadChapter(e.bookId, e.chapterIndex,
              segmentIndex: e.segmentIndex, autoPlay: false)
        ],
      ),

    // =========================================================================
    // From Loading
    // =========================================================================
    (LoadingState s, LoadingComplete e) => (
        ActiveState(
          bookId: s.bookId,
          // Use actual chapter if provided (for auto-skip), otherwise use requested
          chapterIndex: e.actualChapterIndex ?? s.chapterIndex,
          segmentIndex: s.segmentIndex ?? 0,
          isPlaying: true,
          autoScrollEnabled: true,
          segments: e.segments,
          bookTitle: e.bookTitle,
          chapterTitle: e.chapterTitle,
          totalChapters: e.totalChapters,
        ),
        [StartPlayback(s.bookId, e.actualChapterIndex ?? s.chapterIndex, s.segmentIndex ?? 0)],
      ),

    (LoadingState s, LoadingFailed e) => _recoverFromLoadingFailure(s, e),
    
    // No more playable content during loading - treat as book complete
    (LoadingState s, NoMorePlayableContent()) => (
        const IdleState(),
        [
          MarkBookComplete(s.bookId),
          const StopAudio(),
        ],
      ),

    (LoadingState s, BackPressed()) => _cancelLoading(s),

    // Allow play/pause during loading if there's previous playback
    (LoadingState s, PlayPauseToggled()) when s.previousState is ActiveState =>
      (
        s,
        [
          if ((s.previousState! as ActiveState).isPlaying)
            const PauseAudio()
          else
            const PlayAudio()
        ],
      ),

    // =========================================================================
    // From Active
    // =========================================================================

    // Chapter selection - same book, different chapter → Preview
    (ActiveState s, ChapterSelected e)
        when e.bookId == s.bookId && e.chapterIndex != s.chapterIndex =>
      (
        PreviewState(
          viewingBookId: e.bookId,
          viewingChapterIndex: e.chapterIndex,
          viewingSegments: const [],
          isLoadingPreview: true,
          viewingBookTitle: s.bookTitle,
          viewingTotalChapters: s.totalChapters,
          playingBookId: s.bookId,
          playingChapterIndex: s.chapterIndex,
          playingSegmentIndex: s.segmentIndex,
          isPlaying: s.isPlaying,
          playingBookTitle: s.bookTitle,
          playingChapterTitle: s.chapterTitle,
        ),
        [LoadPreviewSegments(e.bookId, e.chapterIndex)],
      ),

    // Chapter selection - same book, same chapter → no-op or seek to start
    (ActiveState s, ChapterSelected e)
        when e.bookId == s.bookId && e.chapterIndex == s.chapterIndex =>
      (
        s.copyWith(segmentIndex: 0, autoScrollEnabled: true),
        [const SeekTo(0), const ScrollToSegment(0)],
      ),

    // Chapter selection - different book → Preview
    (ActiveState s, ChapterSelected e) when e.bookId != s.bookId => (
        PreviewState(
          viewingBookId: e.bookId,
          viewingChapterIndex: e.chapterIndex,
          viewingSegments: const [],
          isLoadingPreview: true,
          playingBookId: s.bookId,
          playingChapterIndex: s.chapterIndex,
          playingSegmentIndex: s.segmentIndex,
          isPlaying: s.isPlaying,
          playingBookTitle: s.bookTitle,
          playingChapterTitle: s.chapterTitle,
        ),
        [LoadPreviewSegments(e.bookId, e.chapterIndex)],
      ),

    // Start listening - same book → no-op (already playing this book)
    (ActiveState s, StartListeningPressed e) when e.bookId == s.bookId => (
        s.copyWith(
          segmentIndex: e.segmentIndex,
          autoScrollEnabled: true,
        ),
        [SeekTo(e.segmentIndex), ScrollToSegment(e.segmentIndex)],
      ),

    // Start listening - different book → Loading
    (ActiveState s, StartListeningPressed e) when e.bookId != s.bookId => (
        LoadingState(
          bookId: e.bookId,
          chapterIndex: e.chapterIndex,
          segmentIndex: e.segmentIndex,
          previousState: s,
        ),
        [
          SavePosition(s.bookId, s.chapterIndex, s.segmentIndex),
          const PauseAudio(),
          LoadChapter(e.bookId, e.chapterIndex,
              segmentIndex: e.segmentIndex, autoPlay: true),
        ],
      ),

    // Segment tap → Seek
    (ActiveState s, SegmentTapped e) => (
        s.copyWith(segmentIndex: e.segmentIndex, autoScrollEnabled: true),
        [SeekTo(e.segmentIndex)],
      ),

    // User scroll → Disable auto-scroll
    (ActiveState s, UserScrolled()) => (
        s.copyWith(autoScrollEnabled: false),
        <PlaybackSideEffect>[],
      ),

    // Jump to audio → Re-enable auto-scroll
    (ActiveState s, JumpToAudioPressed()) => (
        s.copyWith(autoScrollEnabled: true),
        [ScrollToSegment(s.segmentIndex)],
      ),

    // Play/pause toggle
    (ActiveState s, PlayPauseToggled()) => (
        s.copyWith(isPlaying: !s.isPlaying),
        [if (s.isPlaying) const PauseAudio() else const PlayAudio()],
      ),

    // External playback state change (from audio service)
    (ActiveState s, PlaybackStateChanged e) => (
        s.copyWith(isPlaying: e.isPlaying),
        <PlaybackSideEffect>[],
      ),

    // Segment advanced (natural playback progress)
    (ActiveState s, SegmentAdvanced e) => (
        s.copyWith(segmentIndex: e.newSegmentIndex),
        [
          if (s.autoScrollEnabled) ScrollToSegment(e.newSegmentIndex),
        ],
      ),

    // Chapter ended - has next chapter
    (ActiveState s, ChapterEnded())
        when s.chapterIndex < s.totalChapters - 1 =>
      (
        LoadingState(
          bookId: s.bookId,
          chapterIndex: s.chapterIndex + 1,
          segmentIndex: 0,
          previousState: s,
        ),
        [
          MarkChapterComplete(s.bookId, s.chapterIndex),
          LoadChapter(s.bookId, s.chapterIndex + 1, segmentIndex: 0, autoPlay: true),
        ],
      ),

    // Chapter ended - no more chapters (book complete)
    (ActiveState s, ChapterEnded()) => (
        const IdleState(),
        [
          MarkChapterComplete(s.bookId, s.chapterIndex),
          MarkBookComplete(s.bookId),
          const StopAudio(),
        ],
      ),

    // Stop playback
    (ActiveState s, StopPressed()) => (
        const IdleState(),
        [
          SavePosition(s.bookId, s.chapterIndex, s.segmentIndex),
          const StopAudio(),
        ],
      ),

    // Back pressed → Save and exit (state doesn't change, just side effects)
    (ActiveState s, BackPressed()) => (
        s,
        [
          SavePosition(s.bookId, s.chapterIndex, s.segmentIndex),
          const NavigateBack(),
        ],
      ),

    // Auto-save triggered
    (ActiveState s, AutoSaveTriggered()) => (
        s,
        [SavePosition(s.bookId, s.chapterIndex, s.segmentIndex)],
      ),

    // Skip forward
    (ActiveState s, SkipForward())
        when s.segmentIndex < s.segments.length - 1 =>
      (
        s.copyWith(
            segmentIndex: s.segmentIndex + 1, autoScrollEnabled: true),
        [
          SeekTo(s.segmentIndex + 1),
          ScrollToSegment(s.segmentIndex + 1),
        ],
      ),

    // Skip backward
    (ActiveState s, SkipBackward()) when s.segmentIndex > 0 => (
        s.copyWith(
            segmentIndex: s.segmentIndex - 1, autoScrollEnabled: true),
        [
          SeekTo(s.segmentIndex - 1),
          ScrollToSegment(s.segmentIndex - 1),
        ],
      ),

    // Speed change
    (ActiveState s, SpeedChanged e) => (
        s,
        [SetPlaybackSpeed(e.speed)],
      ),

    // Sleep timer
    (ActiveState s, SleepTimerSet e) => (
        s,
        [
          if (e.minutes != null)
            StartSleepTimer(e.minutes!)
          else
            const CancelSleepTimer()
        ],
      ),

    // Sleep timer expired → pause
    (ActiveState s, SleepTimerExpired()) => (
        s.copyWith(isPlaying: false),
        [
          const PauseAudio(),
          SavePosition(s.bookId, s.chapterIndex, s.segmentIndex),
        ],
      ),

    // Audio error in Active → stay in Active but show error
    (ActiveState s, AudioError e) => (
        s.copyWith(isPlaying: false),
        [ShowError(e.error)],
      ),

    // =========================================================================
    // From Preview
    // =========================================================================

    // Preview segments loaded
    (PreviewState s, PreviewSegmentsLoaded e) => (
        s.copyWith(
          // Use actual chapter if provided (for auto-skip), otherwise keep current
          viewingChapterIndex: e.actualChapterIndex ?? s.viewingChapterIndex,
          viewingSegments: e.segments,
          isLoadingPreview: false,
          viewingChapterTitle: e.chapterTitle,
        ),
        <PlaybackSideEffect>[],
      ),

    // Segment tap in preview → commit to preview content
    (PreviewState s, SegmentTapped e) => (
        LoadingState(
          bookId: s.viewingBookId,
          chapterIndex: s.viewingChapterIndex,
          segmentIndex: e.segmentIndex,
          previousState: s,
        ),
        [
          const PauseAudio(),
          SavePosition(s.playingBookId, s.playingChapterIndex,
              s.playingSegmentIndex),
          LoadChapter(s.viewingBookId, s.viewingChapterIndex,
              segmentIndex: e.segmentIndex, autoPlay: true),
        ],
      ),

    // Start listening in preview → commit to preview content
    (PreviewState s, StartListeningPressed e) => (
        LoadingState(
          bookId: e.bookId,
          chapterIndex: e.chapterIndex,
          segmentIndex: e.segmentIndex,
          previousState: s,
        ),
        [
          const PauseAudio(),
          SavePosition(s.playingBookId, s.playingChapterIndex,
              s.playingSegmentIndex),
          LoadChapter(e.bookId, e.chapterIndex,
              segmentIndex: e.segmentIndex, autoPlay: true),
        ],
      ),

    // Mini player tapped → return to playing content
    (PreviewState s, MiniPlayerTapped()) => (
        LoadingState(
          bookId: s.playingBookId,
          chapterIndex: s.playingChapterIndex,
          segmentIndex: s.playingSegmentIndex,
          previousState: s,
        ),
        [
          LoadChapter(s.playingBookId, s.playingChapterIndex,
              segmentIndex: s.playingSegmentIndex, autoPlay: s.isPlaying),
        ],
      ),

    // Chapter selection in preview - same viewing book
    (PreviewState s, ChapterSelected e) when e.bookId == s.viewingBookId => (
        s.copyWith(
          viewingChapterIndex: e.chapterIndex,
          viewingSegments: const [],
          isLoadingPreview: true,
        ),
        [LoadPreviewSegments(e.bookId, e.chapterIndex)],
      ),

    // Chapter selection in preview - different book
    (PreviewState s, ChapterSelected e) when e.bookId != s.viewingBookId => (
        s.copyWith(
          viewingBookId: e.bookId,
          viewingChapterIndex: e.chapterIndex,
          viewingSegments: const [],
          isLoadingPreview: true,
          viewingBookTitle: null, // Will be loaded
          viewingChapterTitle: null,
        ),
        [LoadPreviewSegments(e.bookId, e.chapterIndex)],
      ),

    // Play/pause in preview (via mini player)
    (PreviewState s, PlayPauseToggled()) => (
        s.copyWith(isPlaying: !s.isPlaying),
        [if (s.isPlaying) const PauseAudio() else const PlayAudio()],
      ),

    // External playback state change in preview
    (PreviewState s, PlaybackStateChanged e) => (
        s.copyWith(isPlaying: e.isPlaying),
        <PlaybackSideEffect>[],
      ),

    // Segment advanced in preview (background playback)
    (PreviewState s, SegmentAdvanced e) => (
        s.copyWith(playingSegmentIndex: e.newSegmentIndex),
        <PlaybackSideEffect>[],
      ),

    // Back pressed in preview
    (PreviewState s, BackPressed()) => (
        s,
        [const NavigateBack()],
      ),

    // Audio error in Preview → stay in Preview but stop playback
    (PreviewState s, AudioError e) => (
        s.copyWith(isPlaying: false),
        [ShowError(e.error)],
      ),

    // Chapter ended in preview background playback
    (PreviewState s, ChapterEnded()) => (
        s.copyWith(isPlaying: false),
        [
          MarkChapterComplete(s.playingBookId, s.playingChapterIndex),
          const PauseAudio(),
        ],
      ),

    // =========================================================================
    // NoMorePlayableContent from any state - go to Idle
    // This handles edge cases where this event is dispatched unexpectedly
    // =========================================================================
    (_, NoMorePlayableContent()) => (
        const IdleState(),
        [const StopAudio()],
      ),

    // =========================================================================
    // Default: no change
    // =========================================================================
    _ => (state, <PlaybackSideEffect>[]),
  };
}

/// Handle loading failure - recover to previous state if possible
TransitionResult _recoverFromLoadingFailure(
    LoadingState s, LoadingFailed e) {
  final previous = s.previousState;
  if (previous is ActiveState) {
    // Recover to previous active state
    return (
      previous,
      [ShowError(e.error)],
    );
  } else if (previous is PreviewState) {
    // Recover to previous preview state
    return (
      previous,
      [ShowError(e.error)],
    );
  } else {
    // No previous playback, go to Idle
    return (
      const IdleState(),
      [ShowError(e.error)],
    );
  }
}

/// Handle cancel loading - return to previous state
TransitionResult _cancelLoading(LoadingState s) {
  final previous = s.previousState;
  if (previous != null && previous is! IdleState) {
    return (
      previous,
      [const CancelLoading()],
    );
  } else {
    return (
      const IdleState(),
      [const CancelLoading()],
    );
  }
}
