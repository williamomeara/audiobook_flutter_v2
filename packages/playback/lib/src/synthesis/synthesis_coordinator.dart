import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import '../playback_config.dart';
import 'semaphore.dart';
import 'synthesis_request.dart';

export 'synthesis_request.dart' show SynthesisPriority;

/// Result of a segment becoming ready (either from cache or synthesis).
class SegmentReadyEvent {
  const SegmentReadyEvent({
    required this.segmentIndex,
    required this.cacheKey,
    required this.durationMs,
    required this.wasFromCache,
  });

  final int segmentIndex;
  final CacheKey cacheKey;
  final int durationMs;
  final bool wasFromCache;
}

/// Event emitted when synthesis starts for a segment.
class SegmentSynthesisStartedEvent {
  const SegmentSynthesisStartedEvent({
    required this.segmentIndex,
    required this.cacheKey,
  });

  final int segmentIndex;
  final CacheKey cacheKey;
}

/// Result of a segment synthesis failure.
class SegmentFailedEvent {
  const SegmentFailedEvent({
    required this.segmentIndex,
    required this.cacheKey,
    required this.error,
    required this.isTimeout,
  });

  final int segmentIndex;
  final CacheKey cacheKey;
  final Object error;
  final bool isTimeout;
}

/// Coordinates all synthesis requests with deduplication and concurrency control.
///
/// This is the single source of truth for segment synthesis. All synthesis
/// requests go through this coordinator, which:
/// - Deduplicates requests (same segment won't be synthesized twice)
/// - Respects engine concurrency limits (prevents "busy" errors)
/// - Prioritizes requests (immediate playback > prefetch > background)
/// - Emits events when segments are ready or fail
///
/// Usage:
/// ```dart
/// final coordinator = SynthesisCoordinator(
///   engine: routingEngine,
///   cache: audioCache,
/// );
///
/// // Listen for ready segments
/// coordinator.onSegmentReady.listen((event) {
///   if (event.segmentIndex == currentIndex) {
///     playFromCache(event.cacheKey);
///   }
/// });
///
/// // Queue segments for synthesis
/// await coordinator.queueRange(
///   tracks: tracks,
///   voiceId: 'kokoro_af_bella',
///   startIndex: 0,
///   endIndex: 5,
///   priority: SynthesisPriority.immediate,
/// );
/// ```
class SynthesisCoordinator {
  SynthesisCoordinator({
    required this.engine,
    required this.cache,
    int? maxQueueSize,
  }) : _maxQueueSize = maxQueueSize ?? 100 {
    _startWorker();
  }

  /// The TTS engine for synthesis.
  final RoutingEngine engine;

  /// Audio cache for checking existing segments and getting file paths.
  final AudioCache cache;

  /// Maximum number of requests in queue (prevents memory issues).
  final int _maxQueueSize;

  // ═══════════════════════════════════════════════════════════════════════════
  // Event Streams
  // ═══════════════════════════════════════════════════════════════════════════

  final _segmentReadyController = StreamController<SegmentReadyEvent>.broadcast();
  final _segmentFailedController = StreamController<SegmentFailedEvent>.broadcast();
  final _segmentStartedController = StreamController<SegmentSynthesisStartedEvent>.broadcast();
  final _queueEmptyController = StreamController<void>.broadcast();

  /// Stream of segments that are ready (either from cache or newly synthesized).
  Stream<SegmentReadyEvent> get onSegmentReady => _segmentReadyController.stream;

  /// Stream of segments that failed to synthesize.
  Stream<SegmentFailedEvent> get onSegmentFailed => _segmentFailedController.stream;

  /// Stream of segments that started synthesis (not cached).
  Stream<SegmentSynthesisStartedEvent> get onSynthesisStarted => _segmentStartedController.stream;

  /// Stream that emits when the queue becomes empty.
  Stream<void> get onQueueEmpty => _queueEmptyController.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // State
  // ═══════════════════════════════════════════════════════════════════════════

  /// Priority queue of pending synthesis requests.
  final SplayTreeSet<SynthesisRequest> _queue = SplayTreeSet();

  /// Map from deduplication key to request (for quick lookup and priority upgrade).
  final Map<String, SynthesisRequest> _pendingByKey = {};

  /// Keys currently being synthesized (for deduplication).
  final Set<String> _inFlightKeys = {};

  /// Semaphores per engine type for concurrency control.
  final Map<String, Semaphore> _engineSemaphores = {};

  /// Whether the coordinator has been disposed.
  bool _disposed = false;

  /// Completer to wake up the worker when new items are added.
  Completer<void>? _workerWakeup;

  /// Context key for invalidation (voice + rate).
  String _contextKey = '';

  // Metrics
  int _totalQueued = 0;
  int _totalCompleted = 0;
  int _totalFailed = 0;
  int _cacheHits = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Number of requests currently in queue.
  int get queueLength => _queue.length;

  /// Number of requests currently being synthesized.
  int get inFlightCount => _inFlightKeys.length;

  /// Whether any synthesis is happening.
  bool get isActive => _queue.isNotEmpty || _inFlightKeys.isNotEmpty;

  /// Statistics for debugging.
  Map<String, int> get stats => {
        'queued': _totalQueued,
        'completed': _totalCompleted,
        'failed': _totalFailed,
        'cacheHits': _cacheHits,
        'currentQueue': _queue.length,
        'inFlight': _inFlightKeys.length,
      };

  /// Update context and clear queue if context changed.
  ///
  /// Call this when voice or playback rate changes to invalidate
  /// any pending synthesis that would produce wrong cache keys.
  bool updateContext({
    required String voiceId,
    required double playbackRate,
  }) {
    final effectiveRate = PlaybackConfig.rateIndependentSynthesis
        ? 1.0
        : playbackRate;
    final key = '$voiceId|${effectiveRate.toStringAsFixed(2)}';

    if (_contextKey != key) {
      developer.log('[SynthesisCoordinator] Context changed: $_contextKey -> $key');
      _contextKey = key;
      _clearQueue();
      return true;
    }
    return false;
  }

  /// Queue a range of segments for synthesis.
  ///
  /// - Skips segments already in cache (emits [onSegmentReady] immediately)
  /// - Skips segments already queued or in-flight (upgrades priority if higher)
  /// - Adds new segments to the priority queue
  ///
  /// Returns immediately - synthesis happens asynchronously.
  Future<void> queueRange({
    required List<AudioTrack> tracks,
    required String voiceId,
    required double playbackRate,
    required int startIndex,
    required int endIndex,
    SynthesisPriority priority = SynthesisPriority.prefetch,
  }) async {
    if (_disposed) return;
    if (tracks.isEmpty) return;
    if (startIndex < 0 || startIndex >= tracks.length) return;

    final effectiveEnd = endIndex.clamp(startIndex, tracks.length - 1);
    final effectiveRate = PlaybackConfig.rateIndependentSynthesis
        ? 1.0
        : playbackRate;

    developer.log(
      '[SynthesisCoordinator] queueRange: $startIndex-$effectiveEnd '
      '(${priority.name}, voice: $voiceId)',
    );

    var added = 0;
    var skippedCached = 0;
    var skippedDuplicate = 0;

    for (var i = startIndex; i <= effectiveEnd; i++) {
      final track = tracks[i];
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: voiceId,
        text: track.text,
        playbackRate: CacheKeyGenerator.getSynthesisRate(effectiveRate),
      );
      final dedupeKey = cacheKey.toFilename();

      // Check if already cached
      if (await cache.isReady(cacheKey)) {
        skippedCached++;
        _cacheHits++;
        // Emit ready event immediately for cached segments
        _emitReady(
          segmentIndex: i,
          cacheKey: cacheKey,
          durationMs: await _estimateDurationFromCache(cacheKey),
          wasFromCache: true,
        );
        continue;
      }

      // Check if already in-flight
      if (_inFlightKeys.contains(dedupeKey)) {
        skippedDuplicate++;
        continue;
      }

      // Check if already queued
      final existing = _pendingByKey[dedupeKey];
      if (existing != null) {
        // Upgrade priority if the new request has higher priority
        existing.upgradePriority(priority);
        skippedDuplicate++;
        continue;
      }

      // Respect queue size limit (drop lowest priority if full)
      if (_queue.length >= _maxQueueSize) {
        _dropLowestPriority();
      }

      // Add to queue
      final request = SynthesisRequest(
        track: track,
        voiceId: voiceId,
        playbackRate: effectiveRate,
        segmentIndex: i,
        priority: priority,
        cacheKey: cacheKey,
      );

      _queue.add(request);
      _pendingByKey[dedupeKey] = request;
      _totalQueued++;
      added++;
    }

    developer.log(
      '[SynthesisCoordinator] Queued: $added, cached: $skippedCached, '
      'duplicates: $skippedDuplicate, queue size: ${_queue.length}',
    );

    // Wake up worker if items were added
    if (added > 0) {
      _wakeWorker();
    }
  }

  /// Queue a single segment at immediate priority.
  ///
  /// Convenience method for the current playback segment.
  Future<void> queueImmediate({
    required AudioTrack track,
    required String voiceId,
    required double playbackRate,
    required int segmentIndex,
  }) async {
    await queueRange(
      tracks: [track],
      voiceId: voiceId,
      playbackRate: playbackRate,
      startIndex: 0,
      endIndex: 0,
      priority: SynthesisPriority.immediate,
    );
  }

  /// Check if a segment is ready (in cache).
  Future<bool> isSegmentReady({
    required String voiceId,
    required String text,
    required double playbackRate,
  }) async {
    final effectiveRate = PlaybackConfig.rateIndependentSynthesis
        ? 1.0
        : playbackRate;
    final cacheKey = CacheKeyGenerator.generate(
      voiceId: voiceId,
      text: text,
      playbackRate: CacheKeyGenerator.getSynthesisRate(effectiveRate),
    );
    return cache.isReady(cacheKey);
  }

  /// Cancel all pending synthesis and clear the queue.
  ///
  /// Call this on:
  /// - Chapter change
  /// - Voice change
  /// - Seek to distant position
  void reset() {
    developer.log('[SynthesisCoordinator] Reset called, clearing queue');
    _clearQueue();
  }

  /// Dispose the coordinator and release resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    developer.log('[SynthesisCoordinator] Disposing, stats: $stats');

    _clearQueue();
    _segmentReadyController.close();
    _segmentFailedController.close();
    _segmentStartedController.close();
    _queueEmptyController.close();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Worker Loop
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start the background worker that processes the queue.
  void _startWorker() {
    unawaited(_workerLoop());
  }

  /// Main worker loop - processes queue items respecting concurrency limits.
  Future<void> _workerLoop() async {
    developer.log('[SynthesisCoordinator] Worker started');

    while (!_disposed) {
      // Wait for items if queue is empty
      if (_queue.isEmpty) {
        _workerWakeup = Completer<void>();
        await _workerWakeup!.future;
        _workerWakeup = null;
        if (_disposed) break;
      }

      // Get next request
      final request = _getNextRequest();
      if (request == null) continue;

      // Get semaphore for this engine type
      final engineType = _getEngineType(request.voiceId);
      final semaphore = _getSemaphore(engineType);

      // Wait for concurrency slot (non-blocking if available)
      if (!semaphore.hasAvailable) {
        developer.log(
          '[SynthesisCoordinator] Waiting for $engineType slot '
          '(active: ${semaphore.activeCount}/${semaphore.maxCount})',
        );
      }

      // Process asynchronously to allow multiple concurrent syntheses
      unawaited(_processRequest(request, semaphore));
    }

    developer.log('[SynthesisCoordinator] Worker stopped');
  }

  /// Process a single synthesis request.
  Future<void> _processRequest(
    SynthesisRequest request,
    Semaphore semaphore,
  ) async {
    // Acquire semaphore slot
    await semaphore.acquire();
    if (_disposed) {
      semaphore.release();
      return;
    }

    final dedupeKey = request.deduplicationKey;
    _inFlightKeys.add(dedupeKey);

    try {
      developer.log(
        '[SynthesisCoordinator] Synthesizing segment ${request.segmentIndex} '
        '(${request.priority.name})',
      );

      final stopwatch = Stopwatch()..start();

      // Double-check cache (might have been synthesized by another path)
      if (await cache.isReady(request.cacheKey)) {
        stopwatch.stop();
        developer.log(
          '[SynthesisCoordinator] Segment ${request.segmentIndex} '
          'appeared in cache (race won)',
        );
        _totalCompleted++;
        _cacheHits++;
        _emitReady(
          segmentIndex: request.segmentIndex,
          cacheKey: request.cacheKey,
          durationMs: await _estimateDurationFromCache(request.cacheKey),
          wasFromCache: true,
        );
        return;
      }

      // Emit synthesis started event (not from cache, actually synthesizing)
      _emitSynthesisStarted(
        segmentIndex: request.segmentIndex,
        cacheKey: request.cacheKey,
      );

      // Synthesize with timeout
      final result = await engine
          .synthesizeToWavFile(
            voiceId: request.voiceId,
            text: request.track.text,
            playbackRate: request.playbackRate,
          )
          .timeout(
            PlaybackConfig.synthesisTimeout,
            onTimeout: () => throw TimeoutException(
              'Synthesis timed out after ${PlaybackConfig.synthesisTimeout.inSeconds}s',
            ),
          );

      stopwatch.stop();

      // Check if still relevant (context might have changed)
      if (_disposed) {
        developer.log(
          '[SynthesisCoordinator] Discarding result - coordinator disposed',
        );
        return;
      }

      _totalCompleted++;
      developer.log(
        '[SynthesisCoordinator] ✓ Segment ${request.segmentIndex} '
        'synthesized in ${stopwatch.elapsedMilliseconds}ms '
        '(duration: ${result.durationMs}ms)',
      );

      _emitReady(
        segmentIndex: request.segmentIndex,
        cacheKey: request.cacheKey,
        durationMs: result.durationMs,
        wasFromCache: false,
      );
    } on TimeoutException catch (e) {
      _totalFailed++;
      developer.log(
        '[SynthesisCoordinator] ✗ Segment ${request.segmentIndex} timed out: $e',
      );
      _emitFailed(
        segmentIndex: request.segmentIndex,
        cacheKey: request.cacheKey,
        error: e,
        isTimeout: true,
      );
    } catch (e) {
      _totalFailed++;
      developer.log(
        '[SynthesisCoordinator] ✗ Segment ${request.segmentIndex} failed: $e',
      );
      _emitFailed(
        segmentIndex: request.segmentIndex,
        cacheKey: request.cacheKey,
        error: e,
        isTimeout: false,
      );
    } finally {
      _inFlightKeys.remove(dedupeKey);
      semaphore.release();

      // Check if queue is now empty
      if (_queue.isEmpty && _inFlightKeys.isEmpty) {
        _queueEmptyController.add(null);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get next request from queue.
  SynthesisRequest? _getNextRequest() {
    if (_queue.isEmpty) return null;

    final request = _queue.first;
    _queue.remove(request);
    _pendingByKey.remove(request.deduplicationKey);
    return request;
  }

  /// Wake up the worker loop.
  void _wakeWorker() {
    if (_workerWakeup != null && !_workerWakeup!.isCompleted) {
      _workerWakeup!.complete();
    }
  }

  /// Clear the queue without processing.
  void _clearQueue() {
    _queue.clear();
    _pendingByKey.clear();
    // Note: in-flight requests continue but results may be discarded
    _wakeWorker();
  }

  /// Drop the lowest priority item from the queue.
  void _dropLowestPriority() {
    if (_queue.isEmpty) return;
    final lowest = _queue.last; // Lowest priority is last due to compareTo
    _queue.remove(lowest);
    _pendingByKey.remove(lowest.deduplicationKey);
    developer.log(
      '[SynthesisCoordinator] Dropped segment ${lowest.segmentIndex} '
      '(${lowest.priority.name}) - queue full',
    );
  }

  /// Get or create semaphore for engine type.
  Semaphore _getSemaphore(String engineType) {
    return _engineSemaphores.putIfAbsent(
      engineType,
      () => Semaphore(PlaybackConfig.getConcurrencyForEngine(engineType)),
    );
  }

  /// Extract engine type from voice ID (e.g., "kokoro_af_bella" -> "kokoro").
  String _getEngineType(String voiceId) {
    final parts = voiceId.split('_');
    if (parts.isEmpty) return 'unknown';
    return parts.first.toLowerCase();
  }

  /// Estimate duration from cached file size.
  Future<int> _estimateDurationFromCache(CacheKey cacheKey) async {
    try {
      final file = await cache.fileFor(cacheKey);
      final fileSize = await file.length();
      // Rough estimate: 24kHz, 16-bit mono = ~48KB per second
      return (fileSize / 48).round();
    } catch (_) {
      return 0;
    }
  }

  void _emitReady({
    required int segmentIndex,
    required CacheKey cacheKey,
    required int durationMs,
    required bool wasFromCache,
  }) {
    if (_disposed) return;
    _segmentReadyController.add(SegmentReadyEvent(
      segmentIndex: segmentIndex,
      cacheKey: cacheKey,
      durationMs: durationMs,
      wasFromCache: wasFromCache,
    ));
  }

  void _emitSynthesisStarted({
    required int segmentIndex,
    required CacheKey cacheKey,
  }) {
    if (_disposed) return;
    _segmentStartedController.add(SegmentSynthesisStartedEvent(
      segmentIndex: segmentIndex,
      cacheKey: cacheKey,
    ));
  }

  void _emitFailed({
    required int segmentIndex,
    required CacheKey cacheKey,
    required Object error,
    required bool isTimeout,
  }) {
    if (_disposed) return;
    _segmentFailedController.add(SegmentFailedEvent(
      segmentIndex: segmentIndex,
      cacheKey: cacheKey,
      error: error,
      isTimeout: isTimeout,
    ));
  }
}
