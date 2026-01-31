/// Side effects are actions that need to happen as a result of a state transition.
/// They're returned alongside the new state and executed by a listener.
sealed class PlaybackSideEffect {
  const PlaybackSideEffect();
}

/// Load a chapter and its segments for playback
class LoadChapter extends PlaybackSideEffect {
  final String bookId;
  final int chapterIndex;
  final int? segmentIndex;
  final bool autoPlay;

  const LoadChapter(
    this.bookId,
    this.chapterIndex, {
    this.segmentIndex,
    this.autoPlay = true,
  });
}

/// Load segments for preview display (no playback)
class LoadPreviewSegments extends PlaybackSideEffect {
  final String bookId;
  final int chapterIndex;

  const LoadPreviewSegments(this.bookId, this.chapterIndex);
}

/// Start audio playback from a specific position
class StartPlayback extends PlaybackSideEffect {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;

  const StartPlayback(this.bookId, this.chapterIndex, this.segmentIndex);
}

/// Seek to a specific segment
class SeekTo extends PlaybackSideEffect {
  final int segmentIndex;

  const SeekTo(this.segmentIndex);
}

/// Resume audio playback
class PlayAudio extends PlaybackSideEffect {
  const PlayAudio();
}

/// Pause audio playback
class PauseAudio extends PlaybackSideEffect {
  const PauseAudio();
}

/// Stop audio playback completely
class StopAudio extends PlaybackSideEffect {
  const StopAudio();
}

/// Scroll the UI to show a specific segment
class ScrollToSegment extends PlaybackSideEffect {
  final int segmentIndex;

  const ScrollToSegment(this.segmentIndex);
}

/// Show an error message to the user
class ShowError extends PlaybackSideEffect {
  final String message;

  const ShowError(this.message);
}

/// Navigate to a specific chapter (used when returning from preview)
class NavigateToChapter extends PlaybackSideEffect {
  final String bookId;
  final int chapterIndex;

  const NavigateToChapter(this.bookId, this.chapterIndex);
}

/// Save current playback position to database
class SavePosition extends PlaybackSideEffect {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;

  const SavePosition(this.bookId, this.chapterIndex, this.segmentIndex);
}

/// Mark a chapter as complete
class MarkChapterComplete extends PlaybackSideEffect {
  final String bookId;
  final int chapterIndex;

  const MarkChapterComplete(this.bookId, this.chapterIndex);
}

/// Mark book as complete
class MarkBookComplete extends PlaybackSideEffect {
  final String bookId;

  const MarkBookComplete(this.bookId);
}

/// Set playback speed
class SetPlaybackSpeed extends PlaybackSideEffect {
  final double speed;

  const SetPlaybackSpeed(this.speed);
}

/// Start sleep timer
class StartSleepTimer extends PlaybackSideEffect {
  final int minutes;

  const StartSleepTimer(this.minutes);
}

/// Cancel sleep timer
class CancelSleepTimer extends PlaybackSideEffect {
  const CancelSleepTimer();
}

/// Cancel ongoing loading operation
class CancelLoading extends PlaybackSideEffect {
  const CancelLoading();
}

/// Navigate back (pop route)
class NavigateBack extends PlaybackSideEffect {
  const NavigateBack();
}

/// Skip forward by one segment
class SkipForwardSegment extends PlaybackSideEffect {
  const SkipForwardSegment();
}

/// Skip backward by one segment
class SkipBackwardSegment extends PlaybackSideEffect {
  const SkipBackwardSegment();
}
