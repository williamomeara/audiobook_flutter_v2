import 'package:core_domain/core_domain.dart';

/// Playback state for the audio player.
class PlaybackState {
  const PlaybackState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.currentTrack,
    this.bookId,
    this.queue = const [],
    this.playbackRate = 1.0,
    this.error,
  });

  /// Whether audio is currently playing.
  final bool isPlaying;

  /// Whether the player is buffering (waiting for synthesis).
  final bool isBuffering;

  /// Current track being played.
  final AudioTrack? currentTrack;

  /// Current book ID.
  final String? bookId;

  /// Queue of tracks to play.
  final List<AudioTrack> queue;

  /// Current playback rate.
  final double playbackRate;

  /// Error message if playback failed.
  final String? error;

  /// Current track index in queue, or -1 if not found.
  int get currentIndex {
    if (currentTrack == null) return -1;
    return queue.indexWhere((t) => t.id == currentTrack!.id);
  }

  /// Whether there's a next track available.
  bool get hasNextTrack => currentIndex >= 0 && currentIndex < queue.length - 1;

  /// Whether there's a previous track available.
  bool get hasPreviousTrack => currentIndex > 0;

  /// Empty initial state.
  static const empty = PlaybackState();

  PlaybackState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    AudioTrack? currentTrack,
    String? bookId,
    List<AudioTrack>? queue,
    double? playbackRate,
    String? error,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      currentTrack: currentTrack ?? this.currentTrack,
      bookId: bookId ?? this.bookId,
      queue: queue ?? this.queue,
      playbackRate: playbackRate ?? this.playbackRate,
      error: error,
    );
  }

  @override
  String toString() =>
      'PlaybackState(playing: $isPlaying, buffering: $isBuffering, '
      'track: ${currentTrack?.id}, queueLen: ${queue.length})';
}

/// Audio event types for playback callbacks.
enum AudioEvent {
  /// Audio playback completed successfully.
  completed,

  /// Audio playback was cancelled.
  cancelled,

  /// An error occurred during playback.
  error,
}
