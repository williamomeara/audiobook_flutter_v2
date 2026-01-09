import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

/// Audio handler for system media controls integration.
///
/// This class bridges our app's audio playback with system-level media controls,
/// including lock screen controls, notification shade, and Bluetooth/headphone
/// button events.
class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  AudioServiceHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();

  /// Callbacks for skip actions (to be set by PlaybackController).
  void Function()? onSkipToNextCallback;
  void Function()? onSkipToPreviousCallback;

  /// Initialize player event forwarding.
  void _init() {
    try {
      // Forward player state changes to the media session.
      // Use RxDart to combine multiple streams into a single playback state.
      Rx.combineLatest3<PlaybackEvent, bool, Duration, PlaybackState>(
        _player.playbackEventStream,
        _player.playingStream,
        _player.positionStream,
        (event, playing, position) => _transformEvent(event, playing, position),
      ).listen(
        (state) => playbackState.add(state),
        onError: (error) {
          developer.log('AudioServiceHandler: Error in playback state stream: $error');
        },
      );
    } catch (e) {
      developer.log('AudioServiceHandler: Error during init: $e');
    }
  }

  /// Transform just_audio events to audio_service PlaybackState.
  PlaybackState _transformEvent(
    PlaybackEvent event,
    bool playing,
    Duration position,
  ) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(_player.processingState),
      playing: playing,
      updatePosition: position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  /// Map just_audio processing state to audio_service processing state.
  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// Get the underlying audio player (for direct control if needed).
  AudioPlayer get player => _player;

  /// Update the currently playing media item.
  /// This updates the metadata shown in lock screen and notification controls.
  void updateNowPlaying({
    required String id,
    required String title,
    required String album,
    String? artist,
    Uri? artUri,
    Duration? duration,
    Map<String, dynamic>? extras,
  }) {
    final item = MediaItem(
      id: id,
      title: title,
      album: album,
      artist: artist,
      artUri: artUri,
      duration: duration,
      extras: extras,
    );
    // Use the base class's mediaItem BehaviorSubject
    mediaItem.add(item);
  }

  /// Clear the current media item (e.g., when stopping).
  void clearNowPlaying() {
    mediaItem.add(null);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BaseAudioHandler overrides for system media control events
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    clearNowPlaying();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Delegate to the app's playback controller for chapter/segment navigation.
    onSkipToNextCallback?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    // Delegate to the app's playback controller for chapter/segment navigation.
    onSkipToPreviousCallback?.call();
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> fastForward() async {
    final newPosition = _player.position + const Duration(seconds: 30);
    final duration = _player.duration;
    if (duration != null && newPosition < duration) {
      await _player.seek(newPosition);
    } else if (duration != null) {
      await _player.seek(duration);
    }
  }

  @override
  Future<void> rewind() async {
    final newPosition = _player.position - const Duration(seconds: 30);
    if (newPosition > Duration.zero) {
      await _player.seek(newPosition);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    await _player.dispose();
  }
}
