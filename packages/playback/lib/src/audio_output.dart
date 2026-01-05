import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

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
    _initAudioSession();
    _setupEventListener();
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioEvent> _eventController =
      StreamController<AudioEvent>.broadcast();

  StreamSubscription<PlayerState>? _playerStateSub;
  bool _sessionConfigured = false;

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
          print('[AudioOutput] Audio session interrupted');
          // Another app took focus - pause
          _player.pause();
        } else {
          print('[AudioOutput] Audio session interruption ended');
          // Interruption ended - we could resume here if desired
        }
      });

      // Handle audio becoming noisy (headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        print('[AudioOutput] Audio becoming noisy (headphones unplugged)');
        _player.pause();
      });
      
      _sessionConfigured = true;
      print('[AudioOutput] Audio session configured for speech playback');
    } catch (e) {
      print('[AudioOutput] Warning: Could not configure audio session: $e');
    }
  }

  @override
  Stream<AudioEvent> get events => _eventController.stream;

  void _setupEventListener() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _eventController.add(AudioEvent.completed);
      }
    });

    _player.playbackEventStream.listen((event) {}, onError: (error) {
      _eventController.add(AudioEvent.error);
    });
  }

  @override
  Future<void> playFile(String path, {double playbackRate = 1.0}) async {
    try {
      // Ensure audio session is configured before playing
      await _initAudioSession();
      
      // Verify file exists
      final file = File(path);
      if (!await file.exists()) {
        print('[AudioOutput] ERROR: File does not exist: $path');
        _eventController.add(AudioEvent.error);
        return;
      }

      final fileSize = await file.length();
      print('[AudioOutput] Playing: $path ($fileSize bytes)');
      
      // Set audio source first
      final duration = await _player.setFilePath(path);
      print('[AudioOutput] Source set, duration: $duration');
      
      // Set speed after source is loaded
      await _player.setSpeed(playbackRate);
      print('[AudioOutput] Speed set to: $playbackRate');
      
      // Check player state before playing
      print('[AudioOutput] Player state before play: playing=${_player.playing}, processingState=${_player.processingState}');
      
      // Call play and wait for it to actually start
      print('[AudioOutput] Calling play()...');
      await _player.play();
      
      // Check state immediately after play returns
      print('[AudioOutput] play() returned, playing=${_player.playing}, processingState=${_player.processingState}');
      
      // Wait a short time and check again
      await Future.delayed(const Duration(milliseconds: 100));
      print('[AudioOutput] After 100ms: playing=${_player.playing}, processingState=${_player.processingState}');
      
      print('[AudioOutput] Volume: ${_player.volume}');
    } catch (e, st) {
      print('[AudioOutput] ERROR: $e');
      print('[AudioOutput] Stack: $st');
      _eventController.add(AudioEvent.error);
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _eventController.add(AudioEvent.cancelled);
  }

  @override
  Future<void> setSpeed(double rate) async {
    await _player.setSpeed(rate);
  }

  @override
  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    await _eventController.close();
    await _player.dispose();
  }
}
