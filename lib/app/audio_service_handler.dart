import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

/// Debug logging helper using print for visibility
void _log(String message) {
  // ignore: avoid_print
  print('[AudioServiceHandler] $message');
  developer.log('AudioServiceHandler: $message');
}

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
  AudioServiceHandler() {
    _log('AudioServiceHandler created');
  }

  /// The connected audio player (from the app's playback system).
  AudioPlayer? _player;
  
  /// Subscription to player events.
  StreamSubscription<dynamic>? _playerEventSub;
  
  /// Track last logged state to avoid duplicate logs
  bool? _lastLoggedPlaying;
  AudioProcessingState? _lastLoggedProcessingState;
  
  /// Override flag to prevent play button flickering during segment transitions.
  /// When true, the handler will report `playing: true` regardless of actual 
  /// player state. This should be set when starting a segment transition and
  /// cleared when the new segment starts playing.
  bool _playIntentOverride = false;

  /// Callbacks for skip actions (to be set by PlaybackController).
  void Function()? onSkipToNextCallback;
  void Function()? onSkipToPreviousCallback;
  void Function()? onPlayCallback;
  void Function()? onPauseCallback;
  void Function()? onStopCallback;
  void Function(double speed)? onSpeedChangeCallback;
  
  /// Playback speed presets for cycling
  static const List<double> _speedPresets = [1.0, 1.25, 1.5, 1.75, 2.0];
  
  /// Set the play intent override to prevent play button flickering.
  /// Call with `true` before starting a segment transition and `false` 
  /// when the new segment starts playing.
  void setPlayIntentOverride(bool value) {
    if (_playIntentOverride != value) {
      _log('Play intent override: $value');
      _playIntentOverride = value;
    }
  }

  /// Connect an external AudioPlayer to this handler.
  /// This forwards the player's state to the system media controls.
  void connectPlayer(AudioPlayer player) {
    _log('connectPlayer() called');
    
    // Disconnect any previous player
    _playerEventSub?.cancel();
    _player = player;
    
    try {
      _log('Setting up player state forwarding...');
      
      // Emit initial state immediately to ensure audio service is aware of current state
      final initialState = _transformEvent(
        PlaybackEvent(processingState: player.processingState),
        player.playing,
        player.position,
        player,
      );
      _log('Emitting initial state - playing: ${player.playing}, processingState: ${initialState.processingState}');
      _lastLoggedPlaying = player.playing;
      _lastLoggedProcessingState = initialState.processingState;
      playbackState.add(initialState);
      
      // Forward player state changes to the media session.
      _playerEventSub = Rx.combineLatest3<PlaybackEvent, bool, Duration, PlaybackState>(
        player.playbackEventStream,
        player.playingStream,
        player.positionStream,
        (event, playing, position) {
          final state = _transformEvent(event, playing, position, player);
          // Only log when playing or processingState actually changes (avoid spam from position updates)
          if (playing != _lastLoggedPlaying || state.processingState != _lastLoggedProcessingState) {
            _log('Player state changed - playing: $playing, processingState: ${state.processingState}');
            _lastLoggedPlaying = playing;
            _lastLoggedProcessingState = state.processingState;
          }
          return state;
        },
      ).listen(
        (state) {
          // Only log when state actually changes (avoid spam from position updates)
          if (state.playing != _lastLoggedPlaying || state.processingState != _lastLoggedProcessingState) {
            _log('Broadcasting playbackState - playing: ${state.playing}, processingState: ${state.processingState}');
            _lastLoggedPlaying = state.playing;
            _lastLoggedProcessingState = state.processingState;
          }
          playbackState.add(state);
        },
        onError: (error) {
          _log('ERROR in playback state stream: $error');
        },
      );
      _log('Player connected successfully');
    } catch (e, st) {
      _log('ERROR connecting player: $e');
      _log('Stack trace: $st');
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
    // Create speed label based on current speed
    final speedLabel = '${player.speed}x';
    
    // Use override if set (prevents flicker during segment transitions)
    final effectivePlaying = _playIntentOverride || playing;
    
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        MediaControl.skipToPrevious,
        if (effectivePlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.fastForward,
        // Speed button as custom control
        MediaControl.custom(
          androidIcon: 'drawable/ic_speed',
          label: speedLabel,
          name: 'cycleSpeed',
        ),
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
        MediaAction.fastForward,
        MediaAction.rewind,
        MediaAction.setSpeed,
      },
      androidCompactActionIndices: const [1, 2, 3], // skipPrev, play/pause, skipNext
      processingState: _mapProcessingState(player.processingState),
      playing: effectivePlaying,
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
    _log('updateNowPlaying - title: $title, album: $album, artUri: $artUri, extras: $extras');
    
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
    _log('Setting mediaItem: ${item.title}');
    mediaItem.add(item);
  }

  /// Clear the current media item (e.g., when stopping).
  void clearNowPlaying() {
    _log('clearNowPlaying called');
    mediaItem.add(null);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BaseAudioHandler overrides for system media control events
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<void> play() async {
    _log('play() called from system controls');
    
    // Broadcast playing state immediately to ensure iOS shows controls
    if (_player != null) {
      final state = _transformEvent(
        PlaybackEvent(processingState: _player!.processingState),
        true, // playing
        _player!.position,
        _player!,
      );
      _log('Broadcasting playing=true state before actual play');
      playbackState.add(state);
    }
    
    if (onPlayCallback != null) {
      _log('Calling onPlayCallback');
      onPlayCallback!();
    } else {
      _log('Calling _player.play() directly');
      await _player?.play();
    }
  }

  @override
  Future<void> pause() async {
    _log('pause() called from system controls');
    
    // Broadcast paused state immediately
    if (_player != null) {
      final state = _transformEvent(
        PlaybackEvent(processingState: _player!.processingState),
        false, // not playing
        _player!.position,
        _player!,
      );
      _log('Broadcasting playing=false state before actual pause');
      playbackState.add(state);
    }
    
    if (onPauseCallback != null) {
      _log('Calling onPauseCallback');
      onPauseCallback!();
    } else {
      _log('Calling _player.pause() directly');
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
    // If a specific speed is requested, use it; otherwise cycle to next preset
    if (speed > 0) {
      await _player?.setSpeed(speed);
      onSpeedChangeCallback?.call(speed);
    }
  }
  
  /// Cycle to the next playback speed preset.
  /// Called when user taps the speed button in notification.
  Future<void> cycleSpeed() async {
    final player = _player;
    if (player == null) return;
    
    final currentSpeed = player.speed;
    // Find current preset index and move to next
    int currentIndex = _speedPresets.indexWhere((s) => (s - currentSpeed).abs() < 0.01);
    if (currentIndex < 0) currentIndex = 0;
    
    final nextIndex = (currentIndex + 1) % _speedPresets.length;
    final nextSpeed = _speedPresets[nextIndex];
    
    await player.setSpeed(nextSpeed);
    onSpeedChangeCallback?.call(nextSpeed);
    developer.log('AudioServiceHandler: Speed changed to ${nextSpeed}x');
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

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'cycleSpeed':
        await cycleSpeed();
        break;
      default:
        developer.log('AudioServiceHandler: Unknown custom action: $name');
    }
    return null;
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    await _playerEventSub?.cancel();
    // Don't dispose the player - it's owned by the playback system
  }
}
