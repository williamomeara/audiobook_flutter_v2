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
/// 
/// Note: This handler does NOT create its own AudioPlayer. Instead, it must be
/// connected to the app's existing player via [connectPlayer]. This allows the
/// existing playback architecture to continue working while gaining system
/// media control integration.
class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  AudioServiceHandler();

  /// The connected audio player (from the app's playback system).
  AudioPlayer? _player;
  
  /// Subscription to player events.
  StreamSubscription<dynamic>? _playerEventSub;

  /// Callbacks for skip actions (to be set by PlaybackController).
  void Function()? onSkipToNextCallback;
  void Function()? onSkipToPreviousCallback;
  void Function()? onPlayCallback;
  void Function()? onPauseCallback;
  void Function()? onStopCallback;

  /// Connect an external AudioPlayer to this handler.
  /// This forwards the player's state to the system media controls.
  void connectPlayer(AudioPlayer player) {
    developer.log('AudioServiceHandler: connectPlayer() called');
    
    // Disconnect any previous player
    _playerEventSub?.cancel();
    _player = player;
    
    try {
      developer.log('AudioServiceHandler: Setting up player state forwarding...');
      
      // Forward player state changes to the media session.
      _playerEventSub = Rx.combineLatest3<PlaybackEvent, bool, Duration, PlaybackState>(
        player.playbackEventStream,
        player.playingStream,
        player.positionStream,
        (event, playing, position) {
          final state = _transformEvent(event, playing, position, player);
          developer.log('AudioServiceHandler: Player state changed - playing: $playing, processingState: ${state.processingState}, position: $position');
          return state;
        },
      ).listen(
        (state) {
          developer.log('AudioServiceHandler: Updating playbackState BehaviorSubject');
          playbackState.add(state);
        },
        onError: (error) {
          developer.log('AudioServiceHandler: Error in playback state stream: $error');
        },
      );
      developer.log('AudioServiceHandler: Player connected successfully');
    } catch (e, st) {
      developer.log('AudioServiceHandler: Error connecting player: $e');
      developer.log('AudioServiceHandler: Stack trace: $st');
    }
  }
  
  /// Disconnect the current player.
  void disconnectPlayer() {
    _playerEventSub?.cancel();
    _playerEventSub = null;
    _player = null;
    
    // Reset to idle state
    playbackState.add(PlaybackState(
      controls: [],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  /// Transform just_audio events to audio_service PlaybackState.
  PlaybackState _transformEvent(
    PlaybackEvent event,
    bool playing,
    Duration position,
    AudioPlayer player,
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
      processingState: _mapProcessingState(player.processingState),
      playing: playing,
      updatePosition: position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
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

  /// Get the connected audio player.
  AudioPlayer? get player => _player;

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
    developer.log('AudioServiceHandler: updateNowPlaying() called');
    developer.log('AudioServiceHandler:   id: $id');
    developer.log('AudioServiceHandler:   title: $title');
    developer.log('AudioServiceHandler:   album: $album');
    developer.log('AudioServiceHandler:   artist: $artist');
    developer.log('AudioServiceHandler:   duration: $duration');
    
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
    developer.log('AudioServiceHandler: MediaItem added to stream');
    developer.log('AudioServiceHandler: Updated now playing: $title');
  }

  /// Clear the current media item (e.g., when stopping).
  void clearNowPlaying() {
    mediaItem.add(null);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BaseAudioHandler overrides for system media control events
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> play() async {
    if (onPlayCallback != null) {
      onPlayCallback!();
    } else {
      await _player?.play();
    }
  }

  @override
  Future<void> pause() async {
    if (onPauseCallback != null) {
      onPauseCallback!();
    } else {
      await _player?.pause();
    }
  }

  @override
  Future<void> stop() async {
    if (onStopCallback != null) {
      onStopCallback!();
    } else {
      await _player?.stop();
    }
    clearNowPlaying();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    onSkipToNextCallback?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPreviousCallback?.call();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player?.setSpeed(speed);
  }

  @override
  Future<void> fastForward() async {
    final player = _player;
    if (player == null) return;
    
    final newPosition = player.position + const Duration(seconds: 30);
    final duration = player.duration;
    if (duration != null && newPosition < duration) {
      await player.seek(newPosition);
    } else if (duration != null) {
      await player.seek(duration);
    }
  }

  @override
  Future<void> rewind() async {
    final player = _player;
    if (player == null) return;
    
    final newPosition = player.position - const Duration(seconds: 30);
    if (newPosition > Duration.zero) {
      await player.seek(newPosition);
    } else {
      await player.seek(Duration.zero);
    }
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    await _playerEventSub?.cancel();
    // Don't dispose the player - it's owned by the playback system
  }
}
