import 'package:core_domain/core_domain.dart';

/// All possible user and system events for playback state machine.
sealed class PlaybackEvent {
  const PlaybackEvent();
}

// =============================================================================
// User-Initiated Events
// =============================================================================

/// User clicks main action button on Book Details ("Start Listening" / "Continue Listening")
class StartListeningPressed extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;

  const StartListeningPressed({
    required this.bookId,
    required this.chapterIndex,
    required this.segmentIndex,
  });
}

/// User taps a chapter in chapter list
class ChapterSelected extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;

  const ChapterSelected({
    required this.bookId,
    required this.chapterIndex,
  });
}

/// User taps a segment in text view
class SegmentTapped extends PlaybackEvent {
  final int segmentIndex;

  const SegmentTapped(this.segmentIndex);
}

/// User taps the mini player
class MiniPlayerTapped extends PlaybackEvent {
  const MiniPlayerTapped();
}

/// User navigates back
class BackPressed extends PlaybackEvent {
  const BackPressed();
}

/// User toggles play/pause
class PlayPauseToggled extends PlaybackEvent {
  const PlayPauseToggled();
}

/// User explicitly stops playback
class StopPressed extends PlaybackEvent {
  const StopPressed();
}

/// User manually scrolls the text view
class UserScrolled extends PlaybackEvent {
  const UserScrolled();
}

/// User requests to jump to current audio position
class JumpToAudioPressed extends PlaybackEvent {
  const JumpToAudioPressed();
}

/// User skips forward (by segment or time)
class SkipForward extends PlaybackEvent {
  const SkipForward();
}

/// User skips backward (by segment or time)
class SkipBackward extends PlaybackEvent {
  const SkipBackward();
}

/// User changes playback speed
class SpeedChanged extends PlaybackEvent {
  final double speed;

  const SpeedChanged(this.speed);
}

/// User sets sleep timer
class SleepTimerSet extends PlaybackEvent {
  /// Duration in minutes, null to cancel
  final int? minutes;

  const SleepTimerSet(this.minutes);
}

// =============================================================================
// System Events
// =============================================================================

/// Chapter finished loading successfully
class LoadingComplete extends PlaybackEvent {
  final List<Segment> segments;
  final String? bookTitle;
  final String? chapterTitle;
  final int totalChapters;
  
  /// The actual chapter index that was loaded (may differ from requested due to auto-skip)
  final int? actualChapterIndex;

  const LoadingComplete({
    required this.segments,
    this.bookTitle,
    this.chapterTitle,
    this.totalChapters = 0,
    this.actualChapterIndex,
  });
}

/// Chapter failed to load
class LoadingFailed extends PlaybackEvent {
  final String error;

  const LoadingFailed(this.error);
}

/// Preview segments loaded successfully
class PreviewSegmentsLoaded extends PlaybackEvent {
  final List<Segment> segments;
  final String? chapterTitle;
  
  /// The actual chapter index that was loaded (may differ from requested due to auto-skip)
  final int? actualChapterIndex;

  const PreviewSegmentsLoaded({
    required this.segments,
    this.chapterTitle,
    this.actualChapterIndex,
  });
}

/// Current chapter playback completed
class ChapterEnded extends PlaybackEvent {
  const ChapterEnded();
}

/// No more playable content in the book (all remaining chapters are non-playable)
/// This is different from ChapterEnded - it triggers book completion
class NoMorePlayableContent extends PlaybackEvent {
  const NoMorePlayableContent();
}

/// Audio playback error occurred
class AudioError extends PlaybackEvent {
  final String error;

  const AudioError(this.error);
}

/// Segment playback naturally advanced to next segment
class SegmentAdvanced extends PlaybackEvent {
  final int newSegmentIndex;

  const SegmentAdvanced(this.newSegmentIndex);
}

/// Playback state changed externally (e.g., from audio service)
class PlaybackStateChanged extends PlaybackEvent {
  final bool isPlaying;

  const PlaybackStateChanged(this.isPlaying);
}

/// Auto-save timer triggered
class AutoSaveTriggered extends PlaybackEvent {
  const AutoSaveTriggered();
}

/// Sleep timer expired
class SleepTimerExpired extends PlaybackEvent {
  const SleepTimerExpired();
}

/// User changed voice (needs warmup with new voice)
class VoiceChanged extends PlaybackEvent {
  final String voiceId;

  const VoiceChanged(this.voiceId);
}

/// App was restored and needs to recover playback state
class RestorePlayback extends PlaybackEvent {
  final String bookId;
  final int chapterIndex;
  final int segmentIndex;

  const RestorePlayback({
    required this.bookId,
    required this.chapterIndex,
    required this.segmentIndex,
  });
}
