import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:logging/logging.dart';
import 'package:tts_engines/tts_engines.dart';

import 'audio_output.dart';
import 'buffer_scheduler.dart';
import 'playback_config.dart';
import 'playback_state.dart';
import 'resource_monitor.dart';
import 'synthesis/memory_monitor.dart';
import 'synthesis/parallel_orchestrator.dart';

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
    MemoryMonitor? memoryMonitor,
    int? parallelConcurrency,
  })  : _audioOutput = audioOutput ?? 
            (PlaybackConfig.gaplessPlaybackEnabled 
                ? JustAudioGaplessOutput() 
                : JustAudioOutput()),
        _onStateChange = onStateChange,
        _smartSynthesisManager = smartSynthesisManager,
        _resourceMonitor = resourceMonitor,
        _onSegmentSynthesisStarted = onSegmentSynthesisStarted,
        _onSegmentSynthesisComplete = onSegmentSynthesisComplete,
        _onPlayIntentOverride = onPlayIntentOverride,
        _scheduler = BufferScheduler(resourceMonitor: resourceMonitor),
        _parallelOrchestrator = PlaybackConfig.parallelSynthesisEnabled
            ? ParallelSynthesisOrchestrator(
                maxConcurrency: parallelConcurrency ?? PlaybackConfig.kokoroConcurrency,
                memoryMonitor: memoryMonitor ?? MockMemoryMonitor(),
              )
            : null {
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

  /// Parallel synthesis orchestrator (Phase 4).
  final ParallelSynthesisOrchestrator? _parallelOrchestrator;

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
  
  /// Whether we're using gapless audio output.
  bool get _isGaplessMode => _audioOutput is GaplessAudioOutput;
  
  /// Gapless output (only valid when _isGaplessMode is true).
  GaplessAudioOutput? get _gaplessOutput => 
      _audioOutput is GaplessAudioOutput ? _audioOutput : null;
  
  /// Track which segments are queued in gapless mode (queue index -> cache key).
  /// Used for pinning/unpinning cache entries.
  final Map<int, CacheKey> _gaplessQueuedSegments = {};
  
  /// Number of segments to keep ahead in gapless queue.
  static const int _gaplessLookahead = 3;

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
        
      case AudioEvent.segmentAdvanced:
        // Gapless playback advanced to next segment.
        // Update the current track state to match the new segment.
        if (_isGaplessMode) {
          _handleGaplessSegmentAdvanced();
        }
        break;
    }
  }

  /// Handle gapless segment advanced event.
  /// Advances the current track state and triggers more queueing if needed.
  void _handleGaplessSegmentAdvanced() {
    final gapless = _gaplessOutput;
    if (gapless == null) return;
    
    final playlistIndex = gapless.currentIndex;
    _logger.info('🔄 Gapless segment advanced to playlist index $playlistIndex');
    
    // Find the track at the new segment index relative to the queue
    final currentQueueIndex = _state.currentIndex;
    final nextQueueIndex = currentQueueIndex + 1;
    
    if (nextQueueIndex < _state.queue.length) {
      final nextTrack = _state.queue[nextQueueIndex];
      _speakingTrackId = nextTrack.id;
      
      _updateState(_state.copyWith(
        currentTrack: nextTrack,
      ));
      
      _logger.info('Advanced to track ${nextTrack.segmentIndex}: "${nextTrack.text.substring(0, nextTrack.text.length.clamp(0, 40))}..."');
      
      // Unpin played segment and clean up playlist
      _unpinPlayedGaplessSegments(currentQueueIndex);
      
      // Queue more segments if needed
      _queueMoreSegmentsIfNeeded();
    } else {
      // Reached end of queue
      _logger.info('Reached end of queue after gapless transition');
      _speakingTrackId = null;
      _unpinAllGaplessSegments();
      _updateState(_state.copyWith(
        isPlaying: false,
        isBuffering: false,
      ));
    }
  }
  
  /// Unpin segments that have been played in gapless mode.
  void _unpinPlayedGaplessSegments(int playedQueueIndex) {
    final cacheKey = _gaplessQueuedSegments.remove(playedQueueIndex);
    if (cacheKey != null) {
      cache.unpin(cacheKey);
      _logger.info('Unpinned played segment $playedQueueIndex');
    }
    
    // Remove from gapless playlist to free memory
    final gapless = _gaplessOutput;
    if (gapless != null && gapless.queueLength > 1) {
      // Keep current segment, remove played ones
      unawaited(gapless.removePlayedSegments(keepCount: 1).catchError((e) {
        _logger.warning('Failed to remove played segments: $e');
      }));
    }
  }
  
  /// Unpin all queued segments (called on stop/seek/dispose).
  void _unpinAllGaplessSegments() {
    for (final cacheKey in _gaplessQueuedSegments.values) {
      cache.unpin(cacheKey);
    }
    _gaplessQueuedSegments.clear();
    _logger.info('Unpinned all gapless segments');
  }
  
  /// Queue more segments to the gapless playlist if needed.
  void _queueMoreSegmentsIfNeeded() {
    if (!_isGaplessMode || !_playIntent || _disposed) return;
    
    final gapless = _gaplessOutput;
    if (gapless == null) return;
    
    final currentQueueIndex = _state.currentIndex;
    final segmentsAhead = gapless.queueLength - gapless.currentIndex - 1;
    
    // If we have enough segments queued, don't do anything
    if (segmentsAhead >= _gaplessLookahead) {
      _logger.info('Gapless queue has $segmentsAhead segments ahead, skipping queue');
      return;
    }
    
    // Calculate how many segments we need
    final segmentsNeeded = _gaplessLookahead - segmentsAhead;
    final lastQueuedIndex = _gaplessQueuedSegments.keys.isEmpty 
        ? currentQueueIndex 
        : _gaplessQueuedSegments.keys.reduce((a, b) => a > b ? a : b);
    
    _logger.info('Need to queue $segmentsNeeded more segments (last queued: $lastQueuedIndex)');
    
    // Queue synthesized segments from cache
    final opId = _opId;
    unawaited(_queueSynthesizedSegments(
      startIndex: lastQueuedIndex + 1,
      count: segmentsNeeded,
      opId: opId,
    ).catchError((e, st) {
      _logger.severe('Failed to queue segments', e, st);
    }));
    
    // Also trigger prefetch for segments beyond what we're queueing
    _startImmediateNextPrefetch();
  }
  
  /// Queue synthesized segments from cache to the gapless playlist.
  Future<void> _queueSynthesizedSegments({
    required int startIndex,
    required int count,
    required int opId,
  }) async {
    final gapless = _gaplessOutput;
    if (gapless == null) return;
    
    final voiceId = voiceIdResolver(null);
    
    for (var i = startIndex; i < startIndex + count && i < _state.queue.length; i++) {
      if (!_isCurrentOp(opId) || _isOpCancelled || _disposed || !_playIntent) {
        _logger.info('Gapless queueing cancelled at index $i');
        return;
      }
      
      final track = _state.queue[i];
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: voiceId,
        text: track.text,
        playbackRate: CacheKeyGenerator.getSynthesisRate(_state.playbackRate),
      );
      
      // Check if segment is already synthesized in cache
      if (!await cache.isReady(cacheKey)) {
        _logger.info('Segment $i not in cache yet, waiting for synthesis');
        // Segment not ready - prefetch will handle synthesis
        // Don't block, just stop queueing here
        return;
      }
      
      // Already queued?
      if (_gaplessQueuedSegments.containsKey(i)) {
        continue;
      }
      
      // Get file path and queue it
      final file = await cache.fileFor(cacheKey);
      if (!await file.exists()) {
        _logger.warning('Cache reported ready but file missing: ${file.path}');
        continue;
      }
      
      // Pin the segment before queueing
      cache.pin(cacheKey);
      _gaplessQueuedSegments[i] = cacheKey;
      
      try {
        await gapless.queueSegment(file.path);
        _logger.info('📥 Queued segment $i for gapless playback');
      } catch (e) {
        // Unpin on error
        cache.unpin(cacheKey);
        _gaplessQueuedSegments.remove(i);
        _logger.warning('Failed to queue segment $i: $e');
        return;
      }
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

      // Gapless mode: if next segment is already queued, skip to it
      // Otherwise fall through to standard synthesis
      if (_isGaplessMode && _gaplessQueuedSegments.containsKey(idx + 1)) {
        _logger.info('Gapless skip: segment ${idx + 1} already queued');
        // Unpin and skip the current segment
        _unpinPlayedGaplessSegments(idx);
        _speakingTrackId = nextTrack.id;
        _updateState(_state.copyWith(isBuffering: false));
        _onPlayIntentOverride?.call(false);
        // The gapless player will advance automatically
        return;
      }

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

  /// Update parallel synthesis concurrency (e.g., after engine calibration).
  ///
  /// This is called when calibration completes or when the user switches
  /// to a different TTS engine with different optimal settings.
  void updateParallelConcurrency(int concurrency, {String? source}) {
    _parallelOrchestrator?.updateConcurrency(
      concurrency,
      source: source,
    );
    _logger.info('Parallel concurrency updated to $concurrency (source: ${source ?? "unknown"})');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelSeekDebounce();
    _unpinAllGaplessSegments(); // Clean up gapless pinned segments
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
    // Clear gapless queue and unpin segments
    if (_isGaplessMode) {
      _unpinAllGaplessSegments();
      await _gaplessOutput?.clearQueue();
    }
    await _audioOutput.stop();
    _speakingTrackId = null;
  }
  
  /// Q1: Helper to create synthesis callbacks with current context.
  /// Returns null callbacks if the corresponding field callback is null.
  ({
    void Function(int)? onStarted,
    void Function(int)? onComplete,
  }) _createSynthesisCallbacks() {
    final bookId = _state.bookId ?? '';
    final chapterIndex = _state.queue.isNotEmpty 
        ? _state.queue.first.chapterIndex 
        : 0;
    
    return (
      onStarted: _onSegmentSynthesisStarted != null
          ? (segmentIndex) => _onSegmentSynthesisStarted(bookId, chapterIndex, segmentIndex)
          : null,
      onComplete: _onSegmentSynthesisComplete != null
          ? (segmentIndex) => _onSegmentSynthesisComplete(bookId, chapterIndex, segmentIndex)
          : null,
    );
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
      
      // ════════════════════════════════════════════════════════════════════════
      // CACHE-FIRST: Check if segment is already synthesized or being prefetched
      // This prevents "busy" errors when prefetch is already synthesizing this segment
      // ════════════════════════════════════════════════════════════════════════
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: voiceId,
        text: track.text,
        playbackRate: CacheKeyGenerator.getSynthesisRate(_state.playbackRate),
      );
      
      // Check if already in cache (prefetch may have completed)
      if (await cache.isReady(cacheKey)) {
        _logger.info('✓ Segment already in cache, skipping synthesis');
        final cachedFile = await cache.fileFor(cacheKey);
        
        // Still need to get duration from file for proper playback
        _speakingTrackId = track.id;
        _updateState(_state.copyWith(isBuffering: false));
        _logger.info('Playing from cache: ${cachedFile.path}');
        
        // Gapless mode: queue from cache
        if (_isGaplessMode) {
          cache.pin(cacheKey);
          _gaplessQueuedSegments[_state.currentIndex] = cacheKey;
          
          final gapless = _gaplessOutput!;
          await gapless.queueSegment(cachedFile.path);
          await gapless.playQueue(playbackRate: _state.playbackRate);
          
          _queueMoreSegmentsIfNeeded();
        } else {
          await _audioOutput.playFile(
            cachedFile.path,
            playbackRate: _state.playbackRate,
          );
        }
        
        _logger.info('Audio playback started successfully (from cache)');
        _onPlayIntentOverride?.call(false);
        _startImmediateNextPrefetch();
        _startPrefetchIfNeeded();
        return;
      }
      
      // Not in cache - synthesize (but prefetch might be working on it)
      // Poll briefly in case prefetch is about to complete
      for (var attempt = 0; attempt < 3; attempt++) {
        // H8: Check cancellation before each attempt
        if (!_isCurrentOp(opId) || _isOpCancelled || !_playIntent) {
          _logger.info('Synthesis wait cancelled');
          return;
        }
        
        // Short delay to allow prefetch to complete
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (await cache.isReady(cacheKey)) {
          _logger.info('✓ Prefetch completed during wait (attempt ${attempt + 1})');
          final cachedFile = await cache.fileFor(cacheKey);
          
          _speakingTrackId = track.id;
          _updateState(_state.copyWith(isBuffering: false));
          
          if (_isGaplessMode) {
            cache.pin(cacheKey);
            _gaplessQueuedSegments[_state.currentIndex] = cacheKey;
            
            final gapless = _gaplessOutput!;
            await gapless.queueSegment(cachedFile.path);
            await gapless.playQueue(playbackRate: _state.playbackRate);
            
            _queueMoreSegmentsIfNeeded();
          } else {
            await _audioOutput.playFile(
              cachedFile.path,
              playbackRate: _state.playbackRate,
            );
          }
          
          _logger.info('Audio playback started (prefetch completed during wait)');
          _onPlayIntentOverride?.call(false);
          _startImmediateNextPrefetch();
          _startPrefetchIfNeeded();
          return;
        }
      }
      
      // Still not ready - proceed with synthesis
      _logger.info('Cache miss, starting direct synthesis...');
      
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

      // Gapless mode: queue segment and start gapless playback
      if (_isGaplessMode) {
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: track.text,
          playbackRate: CacheKeyGenerator.getSynthesisRate(_state.playbackRate),
        );
        
        // Pin and track the segment
        cache.pin(cacheKey);
        _gaplessQueuedSegments[_state.currentIndex] = cacheKey;
        
        final gapless = _gaplessOutput!;
        await gapless.queueSegment(result.file.path);
        await gapless.playQueue(playbackRate: _state.playbackRate);
        
        _logger.info('Gapless playback started');
        
        // Queue additional segments from cache
        _queueMoreSegmentsIfNeeded();
      } else {
        // Standard mode: play single file
        await _audioOutput.playFile(
          result.file.path,
          playbackRate: _state.playbackRate,
        );
      }

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
    final callbacks = _createSynthesisCallbacks(); // Q1: Use helper

    // C3: Wrap in error handler to catch unexpected errors
    // Phase 4: Use parallel prefetch if orchestrator is available
    unawaited(_scheduler.runParallelPrefetch(
      engine: engine,
      cache: cache,
      queue: _state.queue,
      voiceId: voiceId,
      playbackRate: _state.playbackRate,
      targetIndex: targetIdx,
      orchestrator: _parallelOrchestrator,
      // H8: Include cancellation check in shouldContinue
      shouldContinue: () => _isCurrentOp(opId) && !_isOpCancelled && _playIntent && !_disposed,
      onSynthesisStarted: callbacks.onStarted,
      onSynthesisComplete: callbacks.onComplete,
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
    final callbacks = _createSynthesisCallbacks(); // Q1: Use helper

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
      onSynthesisStarted: callbacks.onStarted,
      onSynthesisComplete: callbacks.onComplete,
    ).catchError((error, stackTrace) {
      _logger.severe('Immediate next prefetch failed', error, stackTrace);
    }));
  }
}
