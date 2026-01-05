import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import 'audio_output.dart';
import 'buffer_scheduler.dart';
import 'playback_config.dart';
import 'playback_state.dart';

/// Callback for state changes.
typedef StateCallback = void Function(PlaybackState state);

/// Callback for getting the current voice ID.
typedef VoiceIdResolver = String Function(String? bookVoiceId);

/// Interface for playback control.
abstract interface class PlaybackController {
  /// Stream of playback state changes.
  Stream<PlaybackState> get stateStream;

  /// Current playback state.
  PlaybackState get state;

  /// Load a chapter for playback.
  Future<void> loadChapter({
    required List<AudioTrack> tracks,
    required String bookId,
    int startIndex = 0,
    bool autoPlay = true,
  });

  /// Start or resume playback.
  Future<void> play();

  /// Pause playback.
  Future<void> pause();

  /// Seek to a specific track.
  Future<void> seekToTrack(int index, {bool play = true});

  /// Go to next track.
  Future<void> nextTrack();

  /// Go to previous track.
  Future<void> previousTrack();

  /// Set playback rate.
  Future<void> setPlaybackRate(double rate);

  /// Notify of user interaction (suspends prefetch).
  void notifyUserInteraction();

  /// Dispose resources.
  Future<void> dispose();
}

/// Implementation of PlaybackController with synthesis and buffering.
class AudiobookPlaybackController implements PlaybackController {
  AudiobookPlaybackController({
    required this.engine,
    required this.cache,
    required this.voiceIdResolver,
    AudioOutput? audioOutput,
    StateCallback? onStateChange,
  })  : _audioOutput = audioOutput ?? JustAudioOutput(),
        _onStateChange = onStateChange {
    _setupEventListeners();
  }

  /// TTS engine for synthesis.
  final RoutingEngine engine;

  /// Audio cache.
  final AudioCache cache;

  /// Resolves voice ID (may use book-specific or global setting).
  final VoiceIdResolver voiceIdResolver;

  /// Audio output player.
  final AudioOutput _audioOutput;

  /// State change callback.
  final StateCallback? _onStateChange;

  /// Buffer scheduler for prefetch.
  final _scheduler = BufferScheduler();

  /// State stream controller.
  final _stateController = StreamController<PlaybackState>.broadcast();

  /// Current state.
  PlaybackState _state = PlaybackState.empty;

  /// Audio event subscription.
  StreamSubscription<AudioEvent>? _audioSub;

  /// Current operation ID for cancellation.
  int _opId = 0;

  /// User's play intent (true even if auto-paused for buffering).
  bool _playIntent = false;

  /// Currently speaking track ID for completion matching.
  String? _speakingTrackId;

  /// Debounce timer for seeks.
  Timer? _seekDebounceTimer;

  /// Whether the controller has been disposed.
  bool _disposed = false;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  PlaybackState get state => _state;

  void _setupEventListeners() {
    _audioSub = _audioOutput.events.listen(_handleAudioEvent);
  }

  void _handleAudioEvent(AudioEvent event) {
    switch (event) {
      case AudioEvent.completed:
        if (_speakingTrackId == _state.currentTrack?.id) {
          _speakingTrackId = null;
          unawaited(nextTrack());
        }
        break;

      case AudioEvent.cancelled:
        _speakingTrackId = null;
        break;

      case AudioEvent.error:
        _speakingTrackId = null;
        _updateState(_state.copyWith(
          isPlaying: false,
          isBuffering: false,
          error: 'Audio playback error',
        ));
        break;
    }
  }

  void _updateState(PlaybackState newState) {
    if (_disposed) return;
    _state = newState;
    _stateController.add(newState);
    _onStateChange?.call(newState);
  }

  int _newOp() => ++_opId;
  bool _isCurrentOp(int id) => id == _opId;

  @override
  Future<void> loadChapter({
    required List<AudioTrack> tracks,
    required String bookId,
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;

    final opId = _newOp();
    await _stopPlayback();
    if (!_isCurrentOp(opId)) return;

    _scheduler.reset();
    _playIntent = autoPlay;

    final startTrack = tracks[startIndex.clamp(0, tracks.length - 1)];

    _updateState(PlaybackState(
      queue: tracks,
      currentTrack: startTrack,
      bookId: bookId,
      isPlaying: autoPlay,
      isBuffering: autoPlay,
      playbackRate: _state.playbackRate,
    ));

    if (autoPlay) {
      await _speakCurrent(opId: opId);
    }
  }

  @override
  Future<void> play() async {
    if (_state.currentTrack == null) return;

    final opId = _newOp();
    _playIntent = true;
    _cancelSeekDebounce();

    // Already playing this track
    if (_speakingTrackId == _state.currentTrack?.id) return;

    _updateState(_state.copyWith(isPlaying: true, isBuffering: true));
    await _speakCurrent(opId: opId);
  }

  @override
  Future<void> pause() async {
    _newOp();
    _playIntent = false;
    _cancelSeekDebounce();

    await _stopPlayback();
    _scheduler.reset();

    _updateState(_state.copyWith(isPlaying: false, isBuffering: false));
  }

  @override
  Future<void> seekToTrack(int index, {bool play = true}) async {
    if (index < 0 || index >= _state.queue.length) return;

    final opId = _newOp();
    _playIntent = play;
    _cancelSeekDebounce();

    await _stopPlayback();
    if (!_isCurrentOp(opId)) return;

    _scheduler.reset();
    final track = _state.queue[index];

    _updateState(_state.copyWith(
      currentTrack: track,
      isPlaying: play,
      isBuffering: play,
    ));

    if (!play) return;

    // Debounce AI synthesis on rapid seeks
    _seekDebounceTimer = Timer(PlaybackConfig.seekDebounce, () {
      if (!_isCurrentOp(opId) || !_playIntent) return;
      unawaited(_speakCurrent(opId: opId));
    });
  }

  @override
  Future<void> nextTrack() async {
    final idx = _state.currentIndex;
    if (idx < 0) return;

    if (idx < _state.queue.length - 1) {
      // More tracks in queue
      _playIntent = true;
      final opId = _newOp();
      final nextTrack = _state.queue[idx + 1];

      _updateState(_state.copyWith(
        currentTrack: nextTrack,
        isPlaying: true,
        isBuffering: true,
      ));

      await _speakCurrent(opId: opId);
    } else {
      // End of queue
      await pause();
    }
  }

  @override
  Future<void> previousTrack() async {
    final idx = _state.currentIndex;
    if (idx <= 0) return;

    await seekToTrack(idx - 1, play: true);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    final clamped = rate.clamp(
      PlaybackConfig.minPlaybackRate,
      PlaybackConfig.maxPlaybackRate,
    );

    _updateState(_state.copyWith(playbackRate: clamped));
    _scheduler.reset();

    if (_state.isPlaying) {
      await _audioOutput.setSpeed(clamped);
    }
  }

  @override
  void notifyUserInteraction() {
    _scheduler.suspend(
      onResume: () {
        if (!_playIntent || _disposed) return;
        _startPrefetchIfNeeded();
      },
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelSeekDebounce();
    _scheduler.dispose();
    await _audioSub?.cancel();
    await _stateController.close();
    await _audioOutput.dispose();
  }

  void _cancelSeekDebounce() {
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
  }

  Future<void> _stopPlayback() async {
    await _audioOutput.stop();
    _speakingTrackId = null;
  }

  Future<void> _speakCurrent({required int opId}) async {
    final track = _state.currentTrack;
    if (track == null) {
      _updateState(_state.copyWith(isBuffering: false));
      return;
    }

    // TODO: per-book voice selection not yet implemented, always pass null
    final voiceId = voiceIdResolver(null);

    // Update scheduler context
    _scheduler.updateContext(
      bookId: _state.bookId ?? '',
      chapterIndex: track.chapterIndex,
      voiceId: voiceId,
      playbackRate: _state.playbackRate,
      currentIndex: _state.currentIndex,
    );

    // If device TTS, show helpful message (not yet implemented)
    if (voiceId == VoiceIds.device) {
      _updateState(_state.copyWith(
        isBuffering: false,
        error: 'Please select an AI voice in Settings → Voice. Device TTS coming soon.',
      ));
      return;
    }

    try {
      // Synthesize current segment
      final result = await engine.synthesizeToWavFile(
        voiceId: voiceId,
        text: track.text,
        playbackRate: _state.playbackRate,
      );

      if (!_isCurrentOp(opId) || !_playIntent) return;

      // Play the audio
      _speakingTrackId = track.id;
      _updateState(_state.copyWith(isBuffering: false));

      await _audioOutput.playFile(
        result.file.path,
        playbackRate: _state.playbackRate,
      );

      // Start background prefetch
      _startPrefetchIfNeeded();
    } catch (e) {
      if (!_isCurrentOp(opId)) return;

      _updateState(_state.copyWith(
        isPlaying: false,
        isBuffering: false,
        error: e.toString(),
      ));
    }
  }

  void _startPrefetchIfNeeded() {
    // TODO: per-book voice selection not yet implemented, always pass null
    final voiceId = voiceIdResolver(null);
    if (voiceId == VoiceIds.device) return;

    final currentIdx = _state.currentIndex;
    if (currentIdx < 0 || _state.queue.isEmpty) return;

    if (!_scheduler.shouldPrefetch(
      queue: _state.queue,
      currentIndex: currentIdx,
      playbackRate: _state.playbackRate,
    )) {
      return;
    }

    final targetIdx = _scheduler.calculateTargetIndex(
      queue: _state.queue,
      currentIndex: currentIdx,
      playbackRate: _state.playbackRate,
    );

    if (targetIdx <= _scheduler.prefetchedThroughIndex) return;

    final opId = _opId;

    unawaited(_scheduler.runPrefetch(
      engine: engine,
      cache: cache,
      queue: _state.queue,
      voiceId: voiceId,
      playbackRate: _state.playbackRate,
      targetIndex: targetIdx,
      shouldContinue: () => _isCurrentOp(opId) && _playIntent && !_disposed,
    ));
  }
}
