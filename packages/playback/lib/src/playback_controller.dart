import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:logging/logging.dart';
import 'package:tts_engines/tts_engines.dart';

import 'audio_output.dart';
import 'buffer_scheduler.dart';
import 'playback_config.dart';
import 'playback_state.dart';
import 'resource_monitor.dart';
import 'synthesis/auto_calibration_manager.dart';
import 'synthesis/synthesis_coordinator.dart';

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

  /// Notify that the voice selection has changed.
  /// This clears the synthesis queue and prepares for the new voice.
  void notifyVoiceChanged();

  /// Notify of user interaction (suspends prefetch).
  void notifyUserInteraction();

  /// Dispose resources.
  Future<void> dispose();
}

/// Callback for segment synthesis state changes.
/// Parameters: (bookId, chapterIndex, segmentIndex)
typedef SegmentSynthesisCallback = void Function(String bookId, int chapterIndex, int segmentIndex);

/// Callback for when a segment's audio finishes playing.
/// Parameters: (bookId, chapterIndex, segmentIndex)
typedef SegmentAudioCompleteCallback = void Function(String bookId, int chapterIndex, int segmentIndex);

/// Callback to set play intent override for media controls.
typedef PlayIntentOverrideCallback = void Function(bool override);

/// Callback for when a cache entry is registered after synthesis.
/// Used to trigger post-registration processing like compression.
/// Parameter: filename (not full path) of the registered entry.
typedef EntryRegisteredCallback = Future<void> Function(String filename);

/// Callback to check if a segment type should be skipped during playback.
/// Used for the "Skip Code Blocks" setting.
typedef ShouldSkipSegmentTypeCallback = bool Function(SegmentType segmentType);

/// Callback fired when the playback queue ends naturally (last segment finished).
/// This is different from user pause - it indicates all content has been played.
typedef QueueEndedCallback = void Function(String bookId, int chapterIndex);

/// Implementation of PlaybackController with synthesis and buffering.
class AudiobookPlaybackController implements PlaybackController {
  final Logger _logger = Logger('AudiobookPlaybackController');

  AudiobookPlaybackController({
    required this.engine,
    required this.cache,
    required this.voiceIdResolver,
    AudioOutput? audioOutput,
    StateCallback? onStateChange,
    ResourceMonitor? resourceMonitor,
    SegmentSynthesisCallback? onSegmentSynthesisComplete,
    SegmentSynthesisCallback? onSegmentSynthesisStarted,
    SegmentAudioCompleteCallback? onSegmentAudioComplete,
    PlayIntentOverrideCallback? onPlayIntentOverride,
    EntryRegisteredCallback? onEntryRegistered,
    ShouldSkipSegmentTypeCallback? shouldSkipSegmentType,
    QueueEndedCallback? onQueueEnded,
  })  : _audioOutput = audioOutput ?? JustAudioOutput(),
        _onStateChange = onStateChange,
        _resourceMonitor = resourceMonitor,
        _onSegmentSynthesisComplete = onSegmentSynthesisComplete,
        _onSegmentSynthesisStarted = onSegmentSynthesisStarted,
        _onSegmentAudioComplete = onSegmentAudioComplete,
        _onPlayIntentOverride = onPlayIntentOverride,
        _shouldSkipSegmentType = shouldSkipSegmentType,
        _onQueueEnded = onQueueEnded,
        _scheduler = BufferScheduler(resourceMonitor: resourceMonitor),
        _synthesisCoordinator = SynthesisCoordinator(
          engine: engine,
          cache: cache,
          maxQueueSize: PlaybackConfig.synthesisQueueMaxSize,
          onEntryRegistered: onEntryRegistered,
        ) {
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

  /// Resource monitor for battery-aware prefetch.
  final ResourceMonitor? _resourceMonitor;

  /// Callback for segment synthesis complete (for UI feedback).
  final SegmentSynthesisCallback? _onSegmentSynthesisComplete;

  /// Callback for segment synthesis started (for UI feedback).
  final SegmentSynthesisCallback? _onSegmentSynthesisStarted;
  
  /// Callback when a segment's audio finishes playing (for progress tracking).
  final SegmentAudioCompleteCallback? _onSegmentAudioComplete;
  
  /// Callback to set play intent override (prevents play button flicker).
  final PlayIntentOverrideCallback? _onPlayIntentOverride;

  /// Callback to check if a segment type should be skipped.
  final ShouldSkipSegmentTypeCallback? _shouldSkipSegmentType;

  /// Callback when playback queue ends naturally (chapter complete).
  final QueueEndedCallback? _onQueueEnded;

  /// Buffer scheduler for watermark tracking.
  final BufferScheduler _scheduler;

  /// Synthesis coordinator - handles all synthesis with deduplication and priority.
  final SynthesisCoordinator _synthesisCoordinator;

  /// Public getter for synthesis coordinator (for pre-synthesis feature).
  SynthesisCoordinator get synthesisCoordinator => _synthesisCoordinator;

  /// Auto-calibration manager for dynamic concurrency adjustment.
  AutoCalibrationManager? _autoCalibration;

  /// State stream controller.
  final _stateController = StreamController<PlaybackState>.broadcast();

  /// Current state.
  PlaybackState _state = PlaybackState.empty;

  /// Audio event subscription.
  StreamSubscription<AudioEvent>? _audioSub;

  /// Synthesis coordinator subscriptions.
  StreamSubscription<SegmentReadyEvent>? _coordinatorReadySub;
  StreamSubscription<SegmentFailedEvent>? _coordinatorFailedSub;
  StreamSubscription<SegmentSynthesisStartedEvent>? _coordinatorStartedSub;

  /// Completer for waiting on specific segment synthesis (used with coordinator).
  Completer<void>? _waitingForSegmentCompleter;
  int? _waitingForSegmentIndex;

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

  /// Currently pinned cache key (to prevent eviction during playback).
  CacheKey? _pinnedCacheKey;

  /// Whether the controller has been disposed.
  bool _disposed = false;
  
  /// Synthesis start times for RTF calculation.
  final Map<int, DateTime> _synthesisStartTimes = {};

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  PlaybackState get state => _state;

  void _setupEventListeners() {
    _audioSub = _audioOutput.events.listen(_handleAudioEvent);
    _coordinatorReadySub = _synthesisCoordinator.onSegmentReady.listen(_handleCoordinatorReady);
    _coordinatorFailedSub = _synthesisCoordinator.onSegmentFailed.listen(_handleCoordinatorFailed);
    _coordinatorStartedSub = _synthesisCoordinator.onSynthesisStarted.listen(_handleCoordinatorStarted);
    
    // Initialize auto-calibration system
    _initializeAutoCalibration();
  }
  
  /// Initialize the auto-calibration system.
  void _initializeAutoCalibration() {
    _logger.info('[AutoCalibration] Creating manager with semaphores: ${_synthesisCoordinator.engineSemaphores.keys.toList()}');
    
    _autoCalibration = AutoCalibrationManager(
      engineSemaphores: _synthesisCoordinator.engineSemaphores,
      getBufferAheadMs: () {
        // If we're waiting for a segment to synthesize, buffer is effectively 0
        if (_waitingForSegmentCompleter != null) {
          return 0;
        }
        return _scheduler.estimateBufferedAheadMs(
          queue: _state.queue,
          currentIndex: _state.currentIndex,
          playbackRate: _state.playbackRate,
        );
      },
      getPlaybackRate: () => _state.playbackRate,
      isPlaying: () => _state.isPlaying,
    );
    
    // Wire up semaphore creation callback to sync with governor
    _synthesisCoordinator.onSemaphoreCreated = (engineType, semaphore) {
      _logger.info('[AutoCalibration] New semaphore created for $engineType');
      _autoCalibration?.registerSemaphore(engineType, semaphore);
    };
    
    // Initialize asynchronously
    unawaited(_autoCalibration!.initialize().then((_) {
      _logger.info('[AutoCalibration] Initialized successfully');
    }).catchError((e, st) {
      _logger.warning('[AutoCalibration] Failed to initialize: $e\n$st');
    }));
  }

  /// Handle segment synthesis started events from the synthesis coordinator.
  void _handleCoordinatorStarted(SegmentSynthesisStartedEvent event) {
    _logger.info('[Coordinator] Segment ${event.segmentIndex} synthesis started');
    
    // Track start time for RTF calculation
    _synthesisStartTimes[event.segmentIndex] = DateTime.now();
    
    // Notify UI callbacks
    final bookId = _state.bookId ?? '';
    final chapterIndex = _state.currentTrack?.chapterIndex ?? 0;
    _onSegmentSynthesisStarted?.call(bookId, chapterIndex, event.segmentIndex);
  }

  /// Handle segment ready events from the synthesis coordinator.
  void _handleCoordinatorReady(SegmentReadyEvent event) {
    _logger.info('[Coordinator] Segment ${event.segmentIndex} ready (cached: ${event.wasFromCache})');
    
    // Update buffer scheduler to track this segment as ready
    // This is especially important for cached segments after app restart
    unawaited(_scheduler.markSegmentReady(event.segmentIndex));
    
    // Record RTF if this was a real synthesis (not cached)
    if (!event.wasFromCache && _autoCalibration != null) {
      final startTime = _synthesisStartTimes.remove(event.segmentIndex);
      if (startTime != null && event.durationMs > 0) {
        final synthesisTime = DateTime.now().difference(startTime);
        final audioDuration = Duration(milliseconds: event.durationMs);
        
        // Extract engine type from voice ID
        final voiceId = voiceIdResolver(_state.bookId);
        final engineType = voiceId.split('_').firstOrNull ?? 'unknown';
        
        _autoCalibration!.recordSynthesis(
          audioDuration: audioDuration,
          synthesisTime: synthesisTime,
          engineType: engineType,
          voiceId: voiceId,
        );
      }
    }
    
    // Notify UI callbacks
    final bookId = _state.bookId ?? '';
    final chapterIndex = _state.currentTrack?.chapterIndex ?? 0;
    _onSegmentSynthesisComplete?.call(bookId, chapterIndex, event.segmentIndex);
    
    // If we're waiting for this segment, complete the completer
    if (_waitingForSegmentIndex == event.segmentIndex && _waitingForSegmentCompleter != null) {
      _waitingForSegmentCompleter!.complete();
      _waitingForSegmentCompleter = null;
      _waitingForSegmentIndex = null;
    }
  }

  /// Handle segment failed events from the synthesis coordinator.
  void _handleCoordinatorFailed(SegmentFailedEvent event) {
    _logger.warning('[Coordinator] Segment ${event.segmentIndex} failed: ${event.error}');
    
    // If we're waiting for this segment, complete with error
    if (_waitingForSegmentIndex == event.segmentIndex && _waitingForSegmentCompleter != null) {
      _waitingForSegmentCompleter!.completeError(event.error);
      _waitingForSegmentCompleter = null;
      _waitingForSegmentIndex = null;
    }
  }

  void _handleAudioEvent(AudioEvent event) {
    switch (event) {
      case AudioEvent.completed:
        _logger.info('[AudioEvent] Completed. speakingTrackId: $_speakingTrackId, currentTrack: ${_state.currentTrack?.id}');
        if (_speakingTrackId == _state.currentTrack?.id) {
          // Notify that this segment's audio finished playing (for progress tracking)
          final currentTrack = _state.currentTrack;
          final bookId = _state.bookId;
          if (currentTrack != null && bookId != null) {
            _onSegmentAudioComplete?.call(
              bookId,
              currentTrack.chapterIndex,
              currentTrack.segmentIndex,
            );
          }
          
          _speakingTrackId = null;
          // C3: Wrap in error handler to catch unexpected errors
          unawaited(nextTrack().catchError((error, stackTrace) {
            _logger.severe('nextTrack failed after audio completed', error, stackTrace);
          }));
        } else {
          _logger.warning('[AudioEvent] Track ID mismatch, not advancing');
        }
        break;

      case AudioEvent.cancelled:
        _logger.info('[AudioEvent] Cancelled');
        _speakingTrackId = null;
        break;

      case AudioEvent.error:
        _logger.warning('[AudioEvent] Error');
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
    _synthesisCoordinator.reset(); // Reset coordinator queue for new chapter
    _playIntent = autoPlay;

    final startTrack = tracks[startIndex.clamp(0, tracks.length - 1)];
    _logger.info('Starting at track ${startIndex.clamp(0, tracks.length - 1)}: "${startTrack.text.substring(0, startTrack.text.length.clamp(0, 50))}..."');

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

  @override
  Future<void> play() async {
    if (_state.currentTrack == null) return;

    final opId = _newOp();
    _playIntent = true;
    _cancelSeekDebounce();
    
    // Start auto-calibration monitoring
    _autoCalibration?.start();

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
    
    // Stop auto-calibration monitoring
    _autoCalibration?.stop();

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
    _logger.info('[nextTrack] Current index: $idx, queue length: ${_state.queue.length}');
    if (idx < 0) return;

    if (idx < _state.queue.length - 1) {
      // More tracks in queue
      _logger.info('[nextTrack] Advancing from $idx to ${idx + 1}');
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
      // End of queue - chapter is complete
      _logger.info('[nextTrack] End of queue, chapter complete');
      
      // Fire callback before pausing so UI can react
      final currentTrack = _state.currentTrack;
      final bookId = _state.bookId;
      if (currentTrack != null && bookId != null) {
        _onQueueEnded?.call(bookId, currentTrack.chapterIndex);
      }
      
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
        _queueMoreSegmentsIfNeeded();
      },
    );
  }

  @override
  void notifyVoiceChanged() {
    if (_disposed) return;
    
    final newVoiceId = voiceIdResolver(null);
    _logger.info('[VoiceChange] Voice changed, clearing synthesis queue. New voice: $newVoiceId');
    
    // Reset synthesis coordinator - this clears the queue and in-flight synthesis
    _synthesisCoordinator.reset();
    
    // Also reset the buffer scheduler
    _scheduler.reset();
    
    // If currently playing, we need to re-queue from the current position
    // with the new voice. The next play() call will handle this.
    // We don't auto-resynthesize here to avoid synthesizing if user is just
    // browsing voices in settings.
    
    _logger.info('[VoiceChange] Queue cleared. Will use new voice on next play().');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelSeekDebounce();
    _autoCalibration?.dispose();
    _scheduler.dispose();
    _synthesisCoordinator.dispose();
    
    // Unpin any pinned file on dispose
    if (_pinnedCacheKey != null) {
      cache.unpin(_pinnedCacheKey!);
      _pinnedCacheKey = null;
    }
    
    await _coordinatorReadySub?.cancel();
    await _coordinatorFailedSub?.cancel();
    await _coordinatorStartedSub?.cancel();
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
    
    // Unpin the current file when stopping playback
    if (_pinnedCacheKey != null) {
      cache.unpin(_pinnedCacheKey!);
      _pinnedCacheKey = null;
    }
  }

  /// Wait for a segment to become ready (used with unified synthesis coordinator).
  /// Returns when the segment is synthesized and cached.
  Future<void> _waitForSegmentReady(int segmentIndex) async {
    final voiceId = voiceIdResolver(null);
    final track = _state.queue[segmentIndex];
    
    // Check if already in cache
    if (await _synthesisCoordinator.isSegmentReady(
      voiceId: voiceId,
      text: track.text,
      playbackRate: _state.playbackRate,
    )) {
      _logger.info('[Coordinator] Segment $segmentIndex already in cache');
      return;
    }
    
    // Wait for the segment ready event
    _waitingForSegmentIndex = segmentIndex;
    _waitingForSegmentCompleter = Completer<void>();
    
    _logger.info('[Coordinator] Waiting for segment $segmentIndex...');
    
    try {
      await _waitingForSegmentCompleter!.future.timeout(
        PlaybackConfig.synthesisTimeout,
        onTimeout: () {
          throw TimeoutException('Segment $segmentIndex synthesis timed out');
        },
      );
      _logger.info('[Coordinator] Segment $segmentIndex is ready');
    } finally {
      _waitingForSegmentCompleter = null;
      _waitingForSegmentIndex = null;
    }
  }

  /// Play a segment from the cache (used with unified synthesis coordinator).
  Future<void> _playFromCache(int segmentIndex, {required int opId}) async {
    final voiceId = voiceIdResolver(null);
    final track = _state.queue[segmentIndex];
    final effectiveRate = PlaybackConfig.rateIndependentSynthesis 
        ? 1.0 
        : _state.playbackRate;
    
    final cacheKey = CacheKeyGenerator.generate(
      voiceId: voiceId,
      text: track.text,
      playbackRate: CacheKeyGenerator.getSynthesisRate(effectiveRate),
    );
    
    // Pin this file to prevent eviction/compression during playback.
    // Unpin the previous file first.
    if (_pinnedCacheKey != null) {
      cache.unpin(_pinnedCacheKey!);
    }
    cache.pin(cacheKey);
    _pinnedCacheKey = cacheKey;
    
    // Use playableFileFor to get either M4A (compressed) or WAV (uncompressed)
    final file = await cache.playableFileFor(cacheKey);
    if (file == null) {
      _logger.severe('[Coordinator] No playable file found for cache key');
      cache.unpin(cacheKey);
      _pinnedCacheKey = null;
      return;
    }
    
    _speakingTrackId = track.id;
    _updateState(_state.copyWith(isBuffering: false));
    
    await _audioOutput.playFile(
      file.path,
      playbackRate: _state.playbackRate,
    );
    
    _logger.info('[Coordinator] Playing from cache: ${file.path}');
    _onPlayIntentOverride?.call(false);
  }

  /// Queue more segments for synthesis using the coordinator.
  void _queueMoreSegmentsIfNeeded() {
    final voiceId = voiceIdResolver(null);
    if (voiceId == VoiceIds.device) return;
    
    final currentIdx = _state.currentIndex;
    if (currentIdx < 0 || _state.queue.isEmpty) return;
    
    // Calculate how far ahead to queue based on synthesis mode
    final mode = _resourceMonitor?.currentMode ?? SynthesisMode.balanced;
    final maxTracks = mode.maxPrefetchTracks;
    
    if (maxTracks <= 0) return; // JIT-only mode
    
    final endIndex = (currentIdx + maxTracks).clamp(0, _state.queue.length - 1);
    
    // Queue next segments at prefetch priority
    // Get bookId and chapterIndex from the current track (all queued tracks are from same chapter)
    final currentTrack = _state.currentTrack;
    if (currentTrack != null) {
      unawaited(_synthesisCoordinator.queueRange(
        tracks: _state.queue,
        voiceId: voiceId,
        playbackRate: _state.playbackRate,
        startIndex: currentIdx + 1,
        endIndex: endIndex,
        bookId: currentTrack.bookId ?? 'unknown',
        chapterIndex: currentTrack.chapterIndex,
        priority: SynthesisPriority.prefetch,
      ));
    }
  }
  
  Future<void> _speakCurrent({required int opId}) async {
    final track = _state.currentTrack;
    if (track == null) {
      _logger.warning('_speakCurrent called but currentTrack is null');
      _updateState(_state.copyWith(isPlaying: false, isBuffering: false));
      return;
    }

    // Check if this segment type should be skipped (e.g., code blocks)
    final shouldSkip = _shouldSkipSegmentType;
    if (shouldSkip != null && shouldSkip(track.segmentType)) {
      _logger.info('Skipping segment ${track.segmentIndex} (type: ${track.segmentType})');
      // Mark segment as "listened" for progress tracking
      final bookId = _state.bookId;
      if (bookId != null) {
        _onSegmentAudioComplete?.call(
          bookId,
          track.chapterIndex,
          track.segmentIndex,
        );
      }
      // Auto-advance to next track
      if (!_isCurrentOp(opId) || _isOpCancelled) return;
      if (_state.currentIndex + 1 < _state.queue.length) {
        unawaited(nextTrack().catchError((error, stackTrace) {
          _logger.severe('nextTrack failed after skipping segment', error, stackTrace);
        }));
      } else {
        // End of chapter
        _updateState(_state.copyWith(isPlaying: false, isBuffering: false));
      }
      return;
    }

    _logger.info('Speaking track ${track.segmentIndex}: "${track.text.substring(0, track.text.length.clamp(0, 50))}..."');

    // Pass null to the resolver to use the global selected voice when no
    // book-specific voice ID is available. Previously the bookId string was
    // (incorrectly) passed which caused the router to fail to find a matching
    // engine.
    final voiceId = voiceIdResolver(null);
    _logger.info('Using voice: $voiceId');

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
      // Check voice readiness
      _logger.info('[Coordinator] Checking voice readiness...');
      final voiceReadiness = await engine.checkVoiceReady(voiceId);

      if (!voiceReadiness.isReady) {
        _logger.warning('[Coordinator] Voice not ready: ${voiceReadiness.state}');
        _updateState(_state.copyWith(
          isPlaying: false,
          isBuffering: false,
          error: voiceReadiness.nextActionUserShouldTake ??
              'Voice not ready. Please download the required model in Settings.',
        ));
        return;
      }

      // Update coordinator context (clears queue if voice changed)
      _synthesisCoordinator.updateContext(
        voiceId: voiceId,
        playbackRate: _state.playbackRate,
      );

      // Queue current segment at immediate priority
      final track = _state.currentTrack;
      if (track != null) {
        await _synthesisCoordinator.queueRange(
          tracks: _state.queue,
          voiceId: voiceId,
          playbackRate: _state.playbackRate,
          startIndex: _state.currentIndex,
          endIndex: _state.currentIndex,
          bookId: track.bookId ?? 'unknown',
          chapterIndex: track.chapterIndex,
          priority: SynthesisPriority.immediate,
        );

        // Also queue next segment at immediate priority for gapless
        if (_state.currentIndex + 1 < _state.queue.length) {
          await _synthesisCoordinator.queueRange(
            tracks: _state.queue,
            voiceId: voiceId,
            playbackRate: _state.playbackRate,
            startIndex: _state.currentIndex + 1,
            endIndex: _state.currentIndex + 1,
            bookId: track.bookId ?? 'unknown',
            chapterIndex: track.chapterIndex,
            priority: SynthesisPriority.immediate,
          );
        }
      }

      // Wait for current segment to be ready
      await _waitForSegmentReady(_state.currentIndex);

      // H8: Check cancellation after synthesis wait
      if (!_isCurrentOp(opId) || _isOpCancelled || !_playIntent) {
        _logger.info('[Coordinator] Playback cancelled during wait');
        return;
      }

      // Play from cache
      await _playFromCache(_state.currentIndex, opId: opId);

      _logger.info('[Coordinator] Playback started successfully');

      // Queue more segments in background
      _queueMoreSegmentsIfNeeded();
    } catch (e, stackTrace) {
      _logger.severe('[Coordinator] Playback failed', e, stackTrace);
      _onPlayIntentOverride?.call(false);

      if (!_isCurrentOp(opId) || _isOpCancelled) return;

      _updateState(_state.copyWith(
        isPlaying: false,
        isBuffering: false,
        error: e.toString(),
      ));
    }
  }
}
