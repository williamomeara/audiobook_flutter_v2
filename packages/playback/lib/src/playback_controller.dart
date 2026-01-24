import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:logging/logging.dart';
import 'package:tts_engines/tts_engines.dart';

import 'audio_output.dart';
import 'buffer_scheduler.dart';
import 'playback_config.dart';
import 'playback_state.dart';
import 'resource_monitor.dart';

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

/// Callback for segment synthesis state changes.
/// Parameters: (bookId, chapterIndex, segmentIndex)
typedef SegmentSynthesisCallback = void Function(String bookId, int chapterIndex, int segmentIndex);

/// Callback to set play intent override for media controls.
typedef PlayIntentOverrideCallback = void Function(bool override);

/// Implementation of PlaybackController with synthesis and buffering.
class AudiobookPlaybackController implements PlaybackController {
  final Logger _logger = Logger('AudiobookPlaybackController');

  AudiobookPlaybackController({
    required this.engine,
    required this.cache,
    required this.voiceIdResolver,
    AudioOutput? audioOutput,
    StateCallback? onStateChange,
    SmartSynthesisManager? smartSynthesisManager,
    ResourceMonitor? resourceMonitor,
    SegmentSynthesisCallback? onSegmentSynthesisStarted,
    SegmentSynthesisCallback? onSegmentSynthesisComplete,
    PlayIntentOverrideCallback? onPlayIntentOverride,
  })  : _audioOutput = audioOutput ?? JustAudioOutput(),
        _onStateChange = onStateChange,
        _smartSynthesisManager = smartSynthesisManager,
        _resourceMonitor = resourceMonitor,
        _onSegmentSynthesisStarted = onSegmentSynthesisStarted,
        _onSegmentSynthesisComplete = onSegmentSynthesisComplete,
        _onPlayIntentOverride = onPlayIntentOverride,
        _scheduler = BufferScheduler(resourceMonitor: resourceMonitor) {
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

  /// Smart synthesis manager for pre-synthesis strategies.
  final SmartSynthesisManager? _smartSynthesisManager;

  /// Resource monitor for battery-aware prefetch (Phase 2).
  final ResourceMonitor? _resourceMonitor;

  /// Callback for segment synthesis started (for UI feedback).
  final SegmentSynthesisCallback? _onSegmentSynthesisStarted;

  /// Callback for segment synthesis complete (for UI feedback).
  final SegmentSynthesisCallback? _onSegmentSynthesisComplete;
  
  /// Callback to set play intent override (prevents play button flicker).
  final PlayIntentOverrideCallback? _onPlayIntentOverride;

  /// Buffer scheduler for prefetch.
  final BufferScheduler _scheduler;

  /// State stream controller.
  final _stateController = StreamController<PlaybackState>.broadcast();

  /// Current state.
  PlaybackState _state = PlaybackState.empty;

  /// Audio event subscription.
  StreamSubscription<AudioEvent>? _audioSub;

  /// Current operation ID for cancellation.
  int _opId = 0;
  
  /// H8: Cancellation completer for the current operation.
  /// When a new operation starts, this completer is completed to signal
  /// cancellation to any in-flight synthesis operations.
  Completer<void>? _opCancellation;

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
          // C3: Wrap in error handler to catch unexpected errors
          unawaited(nextTrack().catchError((error, stackTrace) {
            _logger.severe('nextTrack failed after audio completed', error, stackTrace);
          }));
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

  /// H8: Create a new operation, cancelling any previous operation.
  /// Returns the new operation ID.
  int _newOp() {
    // Cancel any in-flight operation from the previous opId
    _opCancellation?.complete();
    _opCancellation = Completer<void>();
    return ++_opId;
  }
  
  bool _isCurrentOp(int id) => id == _opId;
  
  /// H8: Check if the current operation has been cancelled.
  bool get _isOpCancelled => _opCancellation?.isCompleted ?? false;

  @override
  Future<void> loadChapter({
    required List<AudioTrack> tracks,
    required String bookId,
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) {
      _logger.warning('loadChapter called with empty tracks array');
      return;
    }

    _logger.info('Loading chapter with ${tracks.length} tracks (start: $startIndex, autoPlay: $autoPlay)');

    final opId = _newOp();
    await _stopPlayback();
    // H8: Check both opId and cancellation token
    if (!_isCurrentOp(opId) || _isOpCancelled) {
      _logger.warning('loadChapter interrupted by new operation');
      return;
    }

    _scheduler.reset();
    _playIntent = autoPlay;

    final startTrack = tracks[startIndex.clamp(0, tracks.length - 1)];
    _logger.info('Starting at track ${startIndex.clamp(0, tracks.length - 1)}: "${startTrack.text.substring(0, startTrack.text.length.clamp(0, 50))}..."');

    // Pre-synthesize first segment(s) using SmartSynthesisManager if available
    if (_smartSynthesisManager != null && autoPlay) {
      final voiceId = voiceIdResolver(null);
      
      _updateState(PlaybackState(
        queue: tracks,
        currentTrack: startTrack,
        bookId: bookId,
        isPlaying: false,
        isBuffering: true,
        playbackRate: _state.playbackRate,
      ));

      // H6: Check voice readiness BEFORE starting pre-synthesis
      final readiness = await engine.checkVoiceReady(voiceId);
      if (!readiness.isReady) {
        _logger.warning('Voice not ready for synthesis: ${readiness.state}');
        _updateState(_state.copyWith(
          isBuffering: false,
          error: readiness.nextActionUserShouldTake ?? 
              'Voice not ready. Please download the voice model first.',
        ));
        return;
      }

      _logger.info('🎤 Starting smart pre-synthesis for voice: $voiceId');
      
      // Get context for synthesis callbacks
      final chapterIndex = tracks.isNotEmpty ? tracks.first.chapterIndex : 0;
      
      try {
        final result = await _smartSynthesisManager.prepareForPlayback(
          engine: engine,
          cache: cache,
          tracks: tracks,
          voiceId: voiceId,
          playbackRate: _state.playbackRate,
          startIndex: startIndex,
        );

        // H8: Check both opId and cancellation token
        if (!_isCurrentOp(opId) || _isOpCancelled) {
          _logger.warning('Pre-synthesis completed but operation was cancelled');
          return;
        }

        if (result.hasErrors) {
          _logger.warning('Pre-synthesis completed with errors: ${result.errors}');
        } else {
          _logger.info('✅ Pre-synthesis complete: ${result.segmentsPrepared} segments in ${result.totalTimeMs}ms');
          
          // Mark pre-synthesized segments as ready for UI feedback
          for (var i = startIndex; i < startIndex + result.segmentsPrepared && i < tracks.length; i++) {
            _onSegmentSynthesisComplete?.call(bookId, chapterIndex, i);
          }
        }

        // ════════════════════════════════════════════════════════════════
        // PHASE 2: Start immediate extended prefetch after pre-synthesis
        // This synthesizes additional segments in background before playback
        // starts, ensuring smooth playback for the first 1-2 minutes.
        // ════════════════════════════════════════════════════════════════
        if (PlaybackConfig.immediatePrefetchOnLoad && 
            (_resourceMonitor?.canPrefetch ?? true)) {
          _logger.info('🚀 [Phase 2] Starting immediate extended prefetch on chapter load');
          _startImmediatePrefetch(
            tracks: tracks,
            startIndex: startIndex,
            voiceId: voiceId,
            opId: opId,
          );
        }
      } catch (e, stackTrace) {
        _logger.severe('Pre-synthesis failed', e, stackTrace);
        // Continue anyway - will synthesize on demand
      }
    }

    _updateState(PlaybackState(
      queue: tracks,
      currentTrack: startTrack,
      bookId: bookId,
      isPlaying: autoPlay,
      isBuffering: autoPlay,
      playbackRate: _state.playbackRate,
    ));

    _logger.info('State updated with ${tracks.length} tracks in queue');

    if (autoPlay) {
      _logger.info('Auto-play enabled, starting playback...');
      await _speakCurrent(opId: opId);
    } else {
      _logger.info('Auto-play disabled, chapter loaded and ready');
    }
  }

  /// Phase 2: Start immediate prefetch in background after pre-synthesis.
  /// This synthesizes extended window (10-15 segments) to ensure smooth playback.
  /// C3: Wraps in error handling to prevent silent failures.
  void _startImmediatePrefetch({
    required List<AudioTrack> tracks,
    required int startIndex,
    required String voiceId,
    required int opId,
  }) {
    // Fire and forget - don't await, run in background
    // C3: Wrap in error handler to catch any unhandled errors
    unawaited(
      _runImmediatePrefetch(
        tracks: tracks,
        startIndex: startIndex,
        voiceId: voiceId,
        opId: opId,
      ).catchError((error, stackTrace) {
        _logger.severe('[Phase 2] Immediate prefetch failed unexpectedly', error, stackTrace);
        // Don't propagate - this is a background operation
        // Playback can continue without prefetch
      }),
    );
  }

  /// Phase 2: Run the immediate prefetch loop.
  /// H8: Checks both opId and cancellation token.
  Future<void> _runImmediatePrefetch({
    required List<AudioTrack> tracks,
    required int startIndex,
    required String voiceId,
    required int opId,
  }) async {
    // Get resource-aware prefetch limits
    final maxTracks = _resourceMonitor?.maxPrefetchTracks ?? 
                      PlaybackConfig.maxPrefetchTracks;
    final endIndex = (startIndex + maxTracks).clamp(0, tracks.length - 1);
    
    _logger.info('[Phase 2] Immediate prefetch: segments ${startIndex + 1} to $endIndex');
    
    // Get context for synthesis callbacks
    final bookId = _state.bookId ?? '';
    final chapterIndex = tracks.isNotEmpty ? tracks.first.chapterIndex : 0;
    
    // Skip first segment (already pre-synthesized), start from second
    for (var i = startIndex + 1; i <= endIndex; i++) {
      // H8: Check both opId and cancellation token for immediate abort
      if (!_isCurrentOp(opId) || _isOpCancelled || _disposed) {
        _logger.info('[Phase 2] Immediate prefetch cancelled (operation changed)');
        return;
      }
      
      final track = tracks[i];
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: voiceId,
        text: track.text,
        playbackRate: CacheKeyGenerator.getSynthesisRate(_state.playbackRate),
      );
      
      // Skip if already cached
      if (await cache.isReady(cacheKey)) {
        _onSegmentSynthesisComplete?.call(bookId, chapterIndex, i);
        continue;
      }
      
      _onSegmentSynthesisStarted?.call(bookId, chapterIndex, i);
      try {
        // H3: Add timeout to prevent hung synthesis from blocking
        await engine.synthesizeToWavFile(
          voiceId: voiceId,
          text: track.text,
          playbackRate: _state.playbackRate,
        ).timeout(
          PlaybackConfig.synthesisTimeout,
          onTimeout: () => throw SynthesisTimeoutException(i, PlaybackConfig.synthesisTimeout),
        );
        
        // H8: Check cancellation after synthesis - discard if operation changed
        if (!_isCurrentOp(opId) || _isOpCancelled) {
          _logger.info('[Phase 2] Discarding prefetch result - operation changed');
          return;
        }
        
        _onSegmentSynthesisComplete?.call(bookId, chapterIndex, i);
        _logger.info('[Phase 2] ✓ Prefetched segment $i');
      } on SynthesisTimeoutException catch (e) {
        _logger.warning('[Phase 2] Segment $i timed out: $e');
        // Continue with other segments
      } catch (e) {
        _logger.warning('[Phase 2] Failed to prefetch segment $i: $e');
        // Continue with other segments
      }
    }
    
    _logger.info('[Phase 2] Immediate prefetch complete');
  }

  @override
  Future<void> play() async {
    if (_state.currentTrack == null) return;

    final opId = _newOp();
    _playIntent = true;
    _cancelSeekDebounce();

    // Already playing this track
    if (_speakingTrackId == _state.currentTrack?.id && !_audioOutput.isPaused) return;

    // If we're resuming the same paused track, just resume instead of re-synthesizing
    if (_speakingTrackId == _state.currentTrack?.id && _audioOutput.isPaused && _audioOutput.hasSource) {
      _logger.info('Resuming paused playback for track: $_speakingTrackId');
      _updateState(_state.copyWith(isPlaying: true, isBuffering: false));
      await _audioOutput.resume();
      return;
    }

    _updateState(_state.copyWith(isPlaying: true, isBuffering: true));
    await _speakCurrent(opId: opId);
  }

  @override
  Future<void> pause() async {
    _newOp();
    _playIntent = false;
    _cancelSeekDebounce();

    // Pause audio instead of stopping - preserves position for resume
    await _audioOutput.pause();
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
    // H8: Check both opId and cancellation token
    if (!_isCurrentOp(opId) || _isOpCancelled) return;

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
      // H8: Check both opId and cancellation token
      if (!_isCurrentOp(opId) || _isOpCancelled || !_playIntent) return;
      // C3: Wrap in error handler to catch unexpected errors
      unawaited(_speakCurrent(opId: opId).catchError((error, stackTrace) {
        _logger.severe('_speakCurrent failed after seek', error, stackTrace);
      }));
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

      // Set override to prevent play button flicker during transition
      _onPlayIntentOverride?.call(true);

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
      _logger.warning('_speakCurrent called but currentTrack is null');
      _updateState(_state.copyWith(isPlaying: false, isBuffering: false));
      return;
    }

    _logger.info('Speaking track ${track.segmentIndex}: "${track.text.substring(0, track.text.length.clamp(0, 50))}..."');

    // Pass null to the resolver to use the global selected voice when no
    // book-specific voice ID is available. Previously the bookId string was
    // (incorrectly) passed which caused the router to fail to find a matching
    // engine.
    final voiceId = voiceIdResolver(null);
    _logger.info('Using voice: $voiceId');

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
      _logger.warning('Device TTS selected but not yet implemented');
      _updateState(_state.copyWith(
        isBuffering: false,
        error: 'Please select an AI voice in Settings → Voice. Device TTS coming soon.',
      ));
      return;
    }

    try {
      // Check if the voice is available before attempting synthesis
      _logger.info('Checking voice readiness...');
      final voiceReadiness = await engine.checkVoiceReady(voiceId);
      
      if (!voiceReadiness.isReady) {
        _logger.warning('Voice not ready: ${voiceReadiness.state}');
        _logger.warning('Next action: ${voiceReadiness.nextActionUserShouldTake}');
        
        _updateState(_state.copyWith(
          isPlaying: false,
          isBuffering: false,
          error: voiceReadiness.nextActionUserShouldTake ?? 
                 'Voice not ready. Please download the required model in Settings.',
        ));
        return;
      }

      _logger.info('Voice is ready, starting synthesis...');
      final synthStart = DateTime.now();
      
      // Synthesize current segment (H3: with timeout to prevent hung playback)
      final result = await engine.synthesizeToWavFile(
        voiceId: voiceId,
        text: track.text,
        playbackRate: _state.playbackRate,
      ).timeout(
        PlaybackConfig.synthesisTimeout,
        onTimeout: () => throw SynthesisTimeoutException(
          _state.currentIndex,
          PlaybackConfig.synthesisTimeout,
        ),
      );

      final synthDuration = DateTime.now().difference(synthStart);
      _logger.info('Synthesis complete in ${synthDuration.inMilliseconds}ms');
      _logger.info('Audio file: ${result.file.path}');
      _logger.info('Duration: ${result.durationMs}ms');

      // H8: Check both opId and cancellation token
      if (!_isCurrentOp(opId) || _isOpCancelled || !_playIntent) {
        _logger.info('Synthesis completed but operation was cancelled or play intent changed');
        return;
      }

      // Play the audio
      _speakingTrackId = track.id;
      _updateState(_state.copyWith(isBuffering: false));
      _logger.info('Starting audio playback...');

      await _audioOutput.playFile(
        result.file.path,
        playbackRate: _state.playbackRate,
      );

      _logger.info('Audio playback started successfully');
      
      // Clear the play intent override - audio is now actually playing
      _onPlayIntentOverride?.call(false);

      // H7: Start prefetching AFTER successful playFile to avoid wasted synthesis on failure
      // Immediately start prefetching the next segment (highest priority)
      _startImmediateNextPrefetch();

      // Start background prefetch for additional segments
      _startPrefetchIfNeeded();
    } on SynthesisTimeoutException catch (e) {
      _logger.severe('Synthesis timed out: $e');
      _onPlayIntentOverride?.call(false);
      
      // H8: Check cancellation token
      if (!_isCurrentOp(opId) || _isOpCancelled) return;
      
      _updateState(_state.copyWith(
        isPlaying: false,
        isBuffering: false,
        error: 'Synthesis timed out. Try skipping to the next segment.',
      ));
    } catch (e, stackTrace) {
      _logger.severe('Synthesis failed for track ${track.id}', e, stackTrace);
      
      // Clear override on error
      _onPlayIntentOverride?.call(false);
      
      // H8: Check cancellation token
      if (!_isCurrentOp(opId) || _isOpCancelled) return;

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
    
    // Get context for synthesis callbacks
    final bookId = _state.bookId ?? '';
    final chapterIndex = _state.queue.isNotEmpty 
        ? _state.queue.first.chapterIndex 
        : 0;

    // C3: Wrap in error handler to catch unexpected errors
    unawaited(_scheduler.runPrefetch(
      engine: engine,
      cache: cache,
      queue: _state.queue,
      voiceId: voiceId,
      playbackRate: _state.playbackRate,
      targetIndex: targetIdx,
      // H8: Include cancellation check in shouldContinue
      shouldContinue: () => _isCurrentOp(opId) && !_isOpCancelled && _playIntent && !_disposed,
      onSynthesisStarted: _onSegmentSynthesisStarted != null
          ? (segmentIndex) => _onSegmentSynthesisStarted(bookId, chapterIndex, segmentIndex)
          : null,
      onSynthesisComplete: _onSegmentSynthesisComplete != null
          ? (segmentIndex) => _onSegmentSynthesisComplete(bookId, chapterIndex, segmentIndex)
          : null,
    ).catchError((error, stackTrace) {
      _logger.severe('Background prefetch failed', error, stackTrace);
    }));
  }

  /// Start immediate prefetch of the next segment with highest priority.
  ///
  /// This bypasses normal watermark checks to ensure the next segment
  /// is always ready before the current one finishes, minimizing gaps.
  void _startImmediateNextPrefetch() {
    final voiceId = voiceIdResolver(null);
    if (voiceId == VoiceIds.device) return;

    final currentIdx = _state.currentIndex;
    if (currentIdx < 0 || _state.queue.isEmpty) return;

    final opId = _opId;
    
    // Get context for synthesis callbacks
    final bookId = _state.bookId ?? '';
    final chapterIndex = _state.queue.isNotEmpty 
        ? _state.queue.first.chapterIndex 
        : 0;

    // C3: Wrap in error handler to catch unexpected errors
    unawaited(_scheduler.prefetchNextSegmentImmediately(
      engine: engine,
      cache: cache,
      queue: _state.queue,
      voiceId: voiceId,
      playbackRate: _state.playbackRate,
      currentIndex: currentIdx,
      // H8: Include cancellation check in shouldContinue
      shouldContinue: () => _isCurrentOp(opId) && !_isOpCancelled && _playIntent && !_disposed,
      onSynthesisStarted: _onSegmentSynthesisStarted != null
          ? (segmentIndex) => _onSegmentSynthesisStarted(bookId, chapterIndex, segmentIndex)
          : null,
      onSynthesisComplete: _onSegmentSynthesisComplete != null
          ? (segmentIndex) => _onSegmentSynthesisComplete(bookId, chapterIndex, segmentIndex)
          : null,
    ).catchError((error, stackTrace) {
      _logger.severe('Immediate next prefetch failed', error, stackTrace);
    }));
  }
}
