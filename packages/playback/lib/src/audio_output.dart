import 'dart:async';
import 'dart:io';

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
    _setupEventListener();
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioEvent> _eventController =
      StreamController<AudioEvent>.broadcast();

  StreamSubscription<PlayerState>? _playerStateSub;

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
      // Verify file exists
      final file = File(path);
      if (!await file.exists()) {
        _eventController.add(AudioEvent.error);
        return;
      }

      await _player.setSpeed(playbackRate);
      await _player.setFilePath(path);
      await _player.play();
    } catch (e) {
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
