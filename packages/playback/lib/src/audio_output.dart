import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_log.dart';
import 'playback_state.dart';

/// Audio output interface for playing synthesized audio files.
abstract interface class AudioOutput {
  /// Stream of audio events.
  Stream<AudioEvent> get events;

  /// Play an audio file at the specified rate.
  Future<void> playFile(String path, {double playbackRate = 1.0});

  /// Pause playback.
  Future<void> pause();

  /// Stop playback and reset.
  Future<void> stop();

  /// Set the playback speed.
  Future<void> setSpeed(double rate);

  /// Dispose of resources.
  Future<void> dispose();
}

/// Implementation of AudioOutput using just_audio.
class JustAudioOutput implements AudioOutput {
  JustAudioOutput() {
    PlaybackLog.info('Initializing JustAudioOutput');
    _initAudioSession();
    _setupEventListener();
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioEvent> _eventController =
      StreamController<AudioEvent>.broadcast();

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  bool _sessionConfigured = false;
  String? _currentFilePath;

  /// Initialize audio session with proper configuration for audiobook playback.
  Future<void> _initAudioSession() async {
    if (_sessionConfigured) return;
    
    try {
      // Set audio session mode for speech content
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      
      // Handle interruptions (calls, other apps)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          PlaybackLog.info('Audio session interrupted');
          // Another app took focus - pause
          _player.pause();
        } else {
          PlaybackLog.info('Audio session interruption ended');
          // Interruption ended - we could resume here if desired
        }
      });

      // Handle audio becoming noisy (headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        PlaybackLog.info('Audio becoming noisy (headphones unplugged)');
        _player.pause();
      });
      
      _sessionConfigured = true;
      PlaybackLog.info('Audio session configured for speech playback');
    } catch (e) {
      PlaybackLog.warning('Could not configure audio session: $e');
    }
  }

  @override
  Stream<AudioEvent> get events => _eventController.stream;

  void _setupEventListener() {
    PlaybackLog.info('Setting up event listeners');
    
    // Listen to player state changes
    _playerStateSub = _player.playerStateStream.listen((state) {
      final processingState = state.processingState;
      final playing = state.playing;
      
      PlaybackLog.debug('Player state changed: $processingState, playing: $playing');
      
      switch (processingState) {
        case ProcessingState.idle:
          PlaybackLog.debug('↳ Idle state');
          break;
        case ProcessingState.loading:
          PlaybackLog.debug('↳ Loading audio...');
          break;
        case ProcessingState.buffering:
          PlaybackLog.debug('↳ Buffering...');
          break;
        case ProcessingState.ready:
          PlaybackLog.debug('↳ Ready to play');
          if (playing) {
            PlaybackLog.debug('↳ Playback started');
          }
          break;
        case ProcessingState.completed:
          PlaybackLog.debug('↳ Track completed');
          _eventController.add(AudioEvent.completed);
          break;
      }
    });

    // Listen to playback events for errors
    _player.playbackEventStream.listen((event) {
      // Detailed logging moved to state stream above
    }, onError: (error) {
      PlaybackLog.error('ERROR in playback stream: $error');
      _eventController.add(AudioEvent.error);
    });
    
    // Listen to position changes (for detailed playback tracking)
    _positionSub = _player.positionStream.listen((position) {
      final duration = _player.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final percent = position.inMilliseconds / duration.inMilliseconds * 100;
        // Log at 25%, 50%, 75%  to track progress without spam
        if ((percent > 24.5 && percent < 25.5) || 
            (percent > 49.5 && percent < 50.5) ||
            (percent > 74.5 && percent < 75.5)) {
          PlaybackLog.debug('Playback progress: ${percent.toStringAsFixed(1)}% '
                '(${position.inSeconds}s / ${duration.inSeconds}s)');
        }
      }
    });
    
    // Listen to duration changes
    _durationSub = _player.durationStream.listen((duration) {
      if (duration != null && _currentFilePath != null) {
        PlaybackLog.debug('Audio duration detected: ${duration.inMilliseconds}ms (${duration.inSeconds}s)');
      }
    });
  }

  @override
  Future<void> playFile(String path, {double playbackRate = 1.0}) async {
    _currentFilePath = path;
    PlaybackLog.progress('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    PlaybackLog.progress('PLAY FILE REQUEST');
    PlaybackLog.progress('Path: $path');
    PlaybackLog.progress('Playback Rate: ${playbackRate}x');
    
    try {
      // Ensure audio session is configured before playing
      await _initAudioSession();
      
      // Verify file exists
      final file = File(path);
      if (!await file.exists()) {
        PlaybackLog.error('File does not exist: $path');
        _eventController.add(AudioEvent.error);
        return;
      }

      final fileSize = await file.length();
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);
      PlaybackLog.progress('✓ File exists: ${fileSizeKB}KB');
      
      // Set audio source first
      PlaybackLog.progress('Setting audio source...');
      final duration = await _player.setFilePath(path);
      PlaybackLog.progress('✓ Source set, duration: ${duration?.inMilliseconds}ms (${duration?.inSeconds}s)');
      
      // Set speed after source is loaded
      await _player.setSpeed(playbackRate);
      PlaybackLog.progress('✓ Speed set to: ${playbackRate}x');
      
      // Check player state before playing
      PlaybackLog.debug('Player state before play: playing=${_player.playing}, processingState=${_player.processingState}');
      
      // Call play and wait for it to actually start
      PlaybackLog.progress('▶ Calling play()...');
      await _player.play();
      
      // Check state immediately after play returns
      PlaybackLog.debug('play() returned, playing=${_player.playing}, processingState=${_player.processingState}');
      
      // Wait a short time and check again
      await Future.delayed(const Duration(milliseconds: 100));
      PlaybackLog.debug('After 100ms: playing=${_player.playing}, processingState=${_player.processingState}');
      PlaybackLog.debug('Volume: ${_player.volume}');
      PlaybackLog.progress('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e, st) {
      PlaybackLog.error('ERROR: $e');
      PlaybackLog.error('Stack: $st');
      _eventController.add(AudioEvent.error);
    }
  }

  @override
  Future<void> pause() async {
    PlaybackLog.progress('⏸ PAUSE requested');
    await _player.pause();
    PlaybackLog.progress('⏸ Paused at position: ${_player.position}');
  }

  @override
  Future<void> stop() async {
    PlaybackLog.progress('⏹ STOP requested');
    await _player.stop();
    _eventController.add(AudioEvent.cancelled);
    PlaybackLog.progress('⏹ Stopped and cancelled');
  }

  @override
  Future<void> setSpeed(double rate) async {
    PlaybackLog.progress('🏃 Setting speed to ${rate}x');
    await _player.setSpeed(rate);
    PlaybackLog.progress('🏃 Speed updated');
  }

  @override
  Future<void> dispose() async {
    PlaybackLog.progress('🗑 Disposing AudioOutput');
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _eventController.close();
    await _player.dispose();
    PlaybackLog.progress('🗑 AudioOutput disposed');
  }
}
