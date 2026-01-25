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
  
  /// Get the underlying AudioPlayer for system media controls integration.
  /// Returns null if the implementation doesn't use just_audio.
  AudioPlayer? get player;
  
  /// Whether audio is currently paused (vs stopped/idle).
  bool get isPaused;
  
  /// Whether there is an active audio source loaded.
  bool get hasSource;

  /// Play an audio file at the specified rate.
  Future<void> playFile(String path, {double playbackRate = 1.0});

  /// Pause playback (preserves position for resume).
  Future<void> pause();
  
  /// Resume playback from paused position.
  Future<void> resume();

  /// Stop playback and reset.
  Future<void> stop();

  /// Set the playback speed.
  Future<void> setSpeed(double rate);

  /// Dispose of resources.
  Future<void> dispose();
}

/// Extended interface for gapless audio output with queue support.
abstract interface class GaplessAudioOutput implements AudioOutput {
  /// Stream of segment index changes (for tracking which segment is playing).
  Stream<int> get currentIndexStream;
  
  /// Current segment index in the queue.
  int get currentIndex;
  
  /// Number of segments currently in the queue.
  int get queueLength;
  
  /// Queue a segment for gapless playback.
  /// Returns the index of the queued segment.
  Future<int> queueSegment(String path);
  
  /// Remove segments from the queue that have already been played.
  /// [keepCount] specifies how many played segments to keep (default: 1 for current).
  Future<void> removePlayedSegments({int keepCount = 1});
  
  /// Clear the entire queue and stop playback.
  Future<void> clearQueue();
  
  /// Start playing from the queue if not already playing.
  Future<void> playQueue({double playbackRate = 1.0});
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
  bool _isPaused = false;
  
  /// Track logged progress milestones to avoid spam
  final Set<int> _loggedProgressMilestones = {};
  
  @override
  AudioPlayer? get player => _player;
  
  @override
  bool get isPaused => _isPaused;
  
  @override
  bool get hasSource => _currentFilePath != null && _player.processingState != ProcessingState.idle;

  /// Initialize audio session with proper configuration for audiobook playback.
  Future<void> _initAudioSession() async {
    if (_sessionConfigured) {
      PlaybackLog.debug('[AudioSession] Already configured, skipping');
      return;
    }
    
    try {
      PlaybackLog.debug('[AudioSession] Configuring audio session...');
      
      // Set audio session mode for speech content
      final session = await AudioSession.instance;
      PlaybackLog.debug('[AudioSession] Got AudioSession instance');
      
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
      PlaybackLog.debug('[AudioSession] Audio session configured with playback category');
      
      // Activate the audio session - required for iOS lock screen controls
      // and Control Center playback controls to appear
      PlaybackLog.debug('[AudioSession] Calling setActive(true)...');
      await session.setActive(true);
      PlaybackLog.debug('[AudioSession] setActive(true) completed - iOS lock screen should work now');
      
      // Handle interruptions (calls, other apps)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          PlaybackLog.debug('[AudioSession] Audio session interrupted');
          _player.pause();
        } else {
          PlaybackLog.debug('[AudioSession] Audio session interruption ended');
        }
      });

      // Handle audio becoming noisy (headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        PlaybackLog.debug('[AudioSession] Audio becoming noisy (headphones unplugged)');
        _player.pause();
      });
      
      _sessionConfigured = true;
      PlaybackLog.debug('[AudioSession] Audio session fully configured and active');
    } catch (e, st) {
      PlaybackLog.error('[AudioSession] ERROR configuring audio session: $e', stackTrace: st);
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
    
    // Listen to position changes (for progress tracking at milestones)
    _positionSub = _player.positionStream.listen((position) {
      final duration = _player.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final percent = position.inMilliseconds / duration.inMilliseconds * 100;
        // Only log once at 25%, 50%, 75% milestones
        final milestone = (percent / 25).floor() * 25;
        if (milestone > 0 && milestone < 100 && !_loggedProgressMilestones.contains(milestone)) {
          _loggedProgressMilestones.add(milestone);
          PlaybackLog.debug('Playback progress: $milestone% '
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
    _loggedProgressMilestones.clear(); // Reset progress milestones for new file
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
    _isPaused = true;
    PlaybackLog.progress('⏸ Paused at position: ${_player.position}');
  }
  
  @override
  Future<void> resume() async {
    PlaybackLog.progress('▶ RESUME requested');
    if (!hasSource) {
      PlaybackLog.warning('Cannot resume: no audio source loaded');
      return;
    }
    await _player.play();
    _isPaused = false;
    PlaybackLog.progress('▶ Resumed from position: ${_player.position}');
  }

  @override
  Future<void> stop() async {
    PlaybackLog.progress('⏹ STOP requested');
    await _player.stop();
    _isPaused = false;
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

/// Gapless audio output implementation using AudioPlayer playlist API.
/// 
/// This implementation queues multiple audio files and plays them
/// sequentially without gaps between segments using just_audio's
/// built-in playlist management (setAudioSources, addAudioSource, etc.).
class JustAudioGaplessOutput implements GaplessAudioOutput {
  JustAudioGaplessOutput() {
    PlaybackLog.info('Initializing JustAudioGaplessOutput (gapless mode)');
    _initAudioSession();
    _setupEventListener();
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioEvent> _eventController =
      StreamController<AudioEvent>.broadcast();
  final StreamController<int> _indexController =
      StreamController<int>.broadcast();

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<Duration?>? _positionSub;
  bool _sessionConfigured = false;
  bool _isPaused = false;
  int _currentIndex = 0;
  int _queueLength = 0;
  
  /// Track segment paths for debugging/logging
  final List<String> _segmentPaths = [];
  
  /// Track logged progress milestones to avoid spam
  final Set<int> _loggedProgressMilestones = {};

  @override
  AudioPlayer? get player => _player;

  @override
  bool get isPaused => _isPaused;

  @override
  bool get hasSource => _queueLength > 0;
  
  @override
  Stream<int> get currentIndexStream => _indexController.stream;
  
  @override
  int get currentIndex => _currentIndex;
  
  @override
  int get queueLength => _queueLength;

  /// Initialize audio session with proper configuration for audiobook playback.
  Future<void> _initAudioSession() async {
    if (_sessionConfigured) {
      PlaybackLog.debug('[AudioSession] Already configured, skipping');
      return;
    }

    try {
      PlaybackLog.debug('[AudioSession] Configuring audio session...');

      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      await session.setActive(true);

      // Handle interruptions (calls, other apps)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          PlaybackLog.debug('[AudioSession] Audio session interrupted');
          _player.pause();
        }
      });

      // Handle audio becoming noisy (headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        PlaybackLog.debug('[AudioSession] Audio becoming noisy');
        _player.pause();
      });

      _sessionConfigured = true;
      PlaybackLog.debug('[AudioSession] Audio session configured and active');
    } catch (e, st) {
      PlaybackLog.error('[AudioSession] ERROR: $e', stackTrace: st);
    }
  }

  @override
  Stream<AudioEvent> get events => _eventController.stream;

  void _setupEventListener() {
    PlaybackLog.info('Setting up gapless event listeners');

    // Listen to player state changes
    _playerStateSub = _player.playerStateStream.listen((state) {
      final processingState = state.processingState;
      final playing = state.playing;

      PlaybackLog.debug(
          'Gapless player state: $processingState, playing: $playing');

      switch (processingState) {
        case ProcessingState.idle:
          break;
        case ProcessingState.loading:
          PlaybackLog.debug('↳ Loading next segment...');
          break;
        case ProcessingState.buffering:
          PlaybackLog.debug('↳ Buffering...');
          break;
        case ProcessingState.ready:
          if (playing) {
            PlaybackLog.debug('↳ Gapless playback active');
          }
          break;
        case ProcessingState.completed:
          PlaybackLog.debug('↳ Queue completed (all segments played)');
          _eventController.add(AudioEvent.completed);
          break;
      }
    });

    // Listen to current index changes - this is key for gapless transitions
    _currentIndexSub = _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex) {
        final oldIndex = _currentIndex;
        _currentIndex = index;
        PlaybackLog.progress(
            '🔄 Gapless transition: segment $oldIndex → $index');
        _indexController.add(index);
        _loggedProgressMilestones.clear(); // Reset for new segment
        
        // Emit segmentAdvanced event for PlaybackController
        _eventController.add(AudioEvent.segmentAdvanced);
      }
    });

    // Listen to position changes for progress tracking
    _positionSub = _player.positionStream.listen((position) {
      final duration = _player.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final percent = position.inMilliseconds / duration.inMilliseconds * 100;
        final milestone = (percent / 25).floor() * 25;
        if (milestone > 0 &&
            milestone < 100 &&
            !_loggedProgressMilestones.contains(milestone)) {
          _loggedProgressMilestones.add(milestone);
          PlaybackLog.debug('Segment progress: $milestone%');
        }
      }
    });

    // Listen for errors
    _player.playbackEventStream.listen((_) {}, onError: (error) {
      PlaybackLog.error('ERROR in gapless playback: $error');
      _eventController.add(AudioEvent.error);
    });
  }

  @override
  Future<int> queueSegment(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      PlaybackLog.error('Cannot queue non-existent file: $path');
      throw FileSystemException('File not found', path);
    }

    final source = AudioSource.file(path);
    
    // Use the new playlist API - addAudioSource
    await _player.addAudioSource(source);
    _segmentPaths.add(path);
    _queueLength++;
    
    final index = _queueLength - 1;
    PlaybackLog.progress('📥 Queued segment $index: ${path.split('/').last}');
    PlaybackLog.debug('Queue length: $_queueLength');
    
    return index;
  }

  @override
  Future<void> removePlayedSegments({int keepCount = 1}) async {
    // Calculate how many segments to remove
    // Keep current and optionally some before it
    final removeCount = _currentIndex - keepCount + 1;
    
    if (removeCount <= 0) {
      PlaybackLog.debug('No segments to remove (current: $_currentIndex, keep: $keepCount)');
      return;
    }

    PlaybackLog.progress('🗑 Removing $removeCount played segments');
    
    // Use the new playlist API - removeAudioSourceRange
    await _player.removeAudioSourceRange(0, removeCount);
    
    // Also clean up our tracking list
    for (var i = 0; i < removeCount && _segmentPaths.isNotEmpty; i++) {
      _segmentPaths.removeAt(0);
    }
    _queueLength -= removeCount;
    if (_queueLength < 0) _queueLength = 0;
    
    // Adjust current index since we removed items before it
    _currentIndex = _currentIndex - removeCount;
    if (_currentIndex < 0) _currentIndex = 0;
    
    PlaybackLog.debug('Queue length after cleanup: $_queueLength');
  }

  @override
  Future<void> clearQueue() async {
    PlaybackLog.progress('🗑 Clearing gapless queue');
    await _player.stop();
    
    // Use the new playlist API - clearAudioSources
    await _player.clearAudioSources();
    
    _segmentPaths.clear();
    _queueLength = 0;
    _currentIndex = 0;
    _isPaused = false;
    PlaybackLog.progress('Queue cleared');
  }

  @override
  Future<void> playQueue({double playbackRate = 1.0}) async {
    if (_queueLength == 0) {
      PlaybackLog.warning('Cannot play empty queue');
      return;
    }

    await _initAudioSession();

    PlaybackLog.progress('▶ Starting gapless playback');
    PlaybackLog.progress('Queue: $_queueLength segments');

    try {
      // With the new playlist API, sources are already added via addAudioSource
      // We just need to set speed and play
      await _player.setSpeed(playbackRate);
      await _player.play();
      _isPaused = false;
      
      PlaybackLog.progress('▶ Gapless playback started');
    } catch (e, st) {
      PlaybackLog.error('ERROR starting gapless playback: $e', stackTrace: st);
      _eventController.add(AudioEvent.error);
    }
  }

  // ========== AudioOutput interface implementation (for backwards compatibility) ==========

  @override
  Future<void> playFile(String path, {double playbackRate = 1.0}) async {
    // For single file playback, clear queue and add just this file
    await clearQueue();
    await queueSegment(path);
    await playQueue(playbackRate: playbackRate);
  }

  @override
  Future<void> pause() async {
    PlaybackLog.progress('⏸ PAUSE requested (gapless)');
    await _player.pause();
    _isPaused = true;
    PlaybackLog.progress('⏸ Paused at segment $_currentIndex');
  }

  @override
  Future<void> resume() async {
    PlaybackLog.progress('▶ RESUME requested (gapless)');
    if (!hasSource) {
      PlaybackLog.warning('Cannot resume: no audio source loaded');
      return;
    }
    await _player.play();
    _isPaused = false;
    PlaybackLog.progress('▶ Resumed at segment $_currentIndex');
  }

  @override
  Future<void> stop() async {
    PlaybackLog.progress('⏹ STOP requested (gapless)');
    await _player.stop();
    _isPaused = false;
    _eventController.add(AudioEvent.cancelled);
    PlaybackLog.progress('⏹ Stopped');
  }

  @override
  Future<void> setSpeed(double rate) async {
    PlaybackLog.progress('🏃 Setting speed to ${rate}x (gapless)');
    await _player.setSpeed(rate);
    PlaybackLog.progress('🏃 Speed updated');
  }

  @override
  Future<void> dispose() async {
    PlaybackLog.progress('🗑 Disposing GaplessAudioOutput');
    await _playerStateSub?.cancel();
    await _currentIndexSub?.cancel();
    await _positionSub?.cancel();
    await _eventController.close();
    await _indexController.close();
    await _player.dispose();
    PlaybackLog.progress('🗑 GaplessAudioOutput disposed');
  }
}
