import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import 'playback_config.dart';
import 'playback_log.dart';
import 'resource_monitor.dart';

/// Simple async lock for protecting shared state.
///
/// Ensures only one async operation can hold the lock at a time.
/// Uses FIFO ordering to prevent starvation.
class _AsyncLock {
  Completer<void>? _lock;

  /// Acquire the lock. Returns when lock is acquired.
  Future<void> acquire() async {
    while (_lock != null) {
      await _lock!.future;
    }
    _lock = Completer<void>();
  }

  /// Release the lock. Must be called after acquire().
  void release() {
    final lock = _lock;
    _lock = null;
    lock?.complete();
  }
}

/// Cancellation token for coordinating prefetch operations.
///
/// When context changes (book/chapter/voice), the token is cancelled
/// to immediately abort any in-progress synthesis operations.
class _CancellationToken {
  Completer<void> _completer = Completer<void>();
  
  /// Whether this token has been cancelled.
  bool get isCancelled => _completer.isCompleted;
  
  /// Future that completes when cancelled.
  Future<void> get future => _completer.future;
  
  /// Cancel this token, signaling all operations to abort.
  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
  
  /// Reset the token for a new context.
  void reset() {
    if (_completer.isCompleted) {
      _completer = Completer<void>();
    }
  }
}

/// Manages audio prefetching for smooth playback.
///
/// The buffer scheduler decides which segments should be synthesized
/// ahead of the current playback position to maintain a smooth
/// listening experience.
///
/// Phase 2 Enhancement: Resource-aware prefetching that adjusts
/// aggressiveness based on battery level and charging state.
class BufferScheduler {
  BufferScheduler({ResourceMonitor? resourceMonitor})
      : _resourceMonitor = resourceMonitor;

  /// Resource monitor for battery-aware prefetch (Phase 2)
  final ResourceMonitor? _resourceMonitor;

  /// Lock for protecting _prefetchedThroughIndex updates.
  final _AsyncLock _indexLock = _AsyncLock();
  
  /// H1: Cancellation token for immediate abort on context change.
  _CancellationToken _cancellationToken = _CancellationToken();

  /// Whether prefetch is currently running.
  bool _isRunning = false;

  /// Index through which prefetch has completed.
  int _prefetchedThroughIndex = -1;

  /// Context key for invalidation on voice/book change.
  /// Initialized to a sentinel value to ensure explicit context setup is required.
  static const _uninitializedContext = '__uninitialized__';
  String _contextKey = _uninitializedContext;

  /// Whether prefetch is temporarily suspended.
  bool _isSuspended = false;

  /// Timer for resuming after suspension.
  Timer? _resumeTimer;

  // Getters
  bool get isRunning => _isRunning;
  int get prefetchedThroughIndex => _prefetchedThroughIndex;
  bool get isSuspended => _isSuspended;
  
  /// Current synthesis mode from resource monitor
  SynthesisMode get synthesisMode =>
      _resourceMonitor?.currentMode ?? SynthesisMode.balanced;

  /// Reset scheduler state for new chapter/context.
  /// H1: Cancels any in-progress prefetch operations immediately.
  void reset() {
    // H1: Cancel any in-progress operations immediately
    _cancellationToken.cancel();
    _cancellationToken = _CancellationToken();
    
    _isRunning = false;
    _prefetchedThroughIndex = -1;
    _contextKey = _uninitializedContext;
  }

  /// Dispose resources.
  void dispose() {
    _resumeTimer?.cancel();
    _cancellationToken.cancel();
  }

  /// Safely update _prefetchedThroughIndex with lock protection.
  /// Only updates if newIndex is greater than current value.
  Future<void> _updatePrefetchedIndex(int newIndex) async {
    await _indexLock.acquire();
    try {
      if (newIndex > _prefetchedThroughIndex) {
        _prefetchedThroughIndex = newIndex;
      }
    } finally {
      _indexLock.release();
    }
  }

  /// Update context and return true if context changed.
  /// H1: Cancels any in-progress prefetch operations when context changes.
  bool updateContext({
    required String bookId,
    required int chapterIndex,
    required String voiceId,
    required double playbackRate,
    required int currentIndex,
  }) {
    final key = '$bookId|$chapterIndex|$voiceId|${playbackRate.toStringAsFixed(2)}';
    if (_contextKey != key) {
      // H1: Cancel any in-progress operations when context changes
      _cancellationToken.cancel();
      _cancellationToken = _CancellationToken();
      
      _contextKey = key;
      _prefetchedThroughIndex = currentIndex;
      return true;
    }
    return false;
  }

  /// Estimate buffered audio ahead of current position.
  int estimateBufferedAheadMs({
    required List<AudioTrack> queue,
    required int currentIndex,
    required double playbackRate,
  }) {
    if (queue.isEmpty || currentIndex < 0) return 0;
    if (_prefetchedThroughIndex <= currentIndex) return 0;

    var ms = 0;
    final end = _prefetchedThroughIndex.clamp(0, queue.length - 1);
    for (var i = currentIndex + 1; i <= end; i++) {
      ms += estimateDurationMs(queue[i].text, playbackRate: playbackRate);
    }
    return ms;
  }

  /// Check if prefetch should start based on buffer level.
  /// Phase 2: Now considers resource constraints.
  bool shouldPrefetch({
    required List<AudioTrack> queue,
    required int currentIndex,
    required double playbackRate,
  }) {
    // Phase 2: Check if resources allow prefetching
    if (_resourceMonitor != null && !_resourceMonitor.canPrefetch) {
      PlaybackLog.debug('Prefetch disabled due to low battery (mode: $synthesisMode)');
      return false;
    }
    
    if (_isSuspended) {
      PlaybackLog.debug('Prefetch suspended, not starting');
      return false;
    }
    if (_isRunning) {
      PlaybackLog.debug('Prefetch already running');
      return false;
    }

    final bufferedMs = estimateBufferedAheadMs(
      queue: queue,
      currentIndex: currentIndex,
      playbackRate: playbackRate,
    );

    final bufferedSec = (bufferedMs / 1000).toStringAsFixed(1);
    final lowWaterSec = (PlaybackConfig.lowWatermarkMs / 1000).toStringAsFixed(1);
    final shouldStart = bufferedMs < PlaybackConfig.lowWatermarkMs;
    
    PlaybackLog.debug('Buffer check: ${bufferedSec}s buffered (threshold: ${lowWaterSec}s), mode: $synthesisMode → ${shouldStart ? "START PREFETCH" : "no prefetch needed"}');
    
    return shouldStart;
  }

  /// Calculate target prefetch index.
  /// Phase 2: Uses resource-aware prefetch window.
  int calculateTargetIndex({
    required List<AudioTrack> queue,
    required int currentIndex,
    required double playbackRate,
  }) {
    // Phase 2: Get resource-aware limits
    final maxTracks = _resourceMonitor?.maxPrefetchTracks ?? 
                      PlaybackConfig.maxPrefetchTracks;
    final targetBufferMs = _resourceMonitor?.bufferTargetMs ?? 
                           PlaybackConfig.bufferTargetMs;
    
    PlaybackLog.debug('Calculating target index from current=$currentIndex (mode: $synthesisMode, maxTracks: $maxTracks)');
    
    var targetIdx = currentIndex + 1;
    var accMs = 0;
    final maxIdx = currentIndex + maxTracks;

    for (var i = currentIndex + 1; i < queue.length && i <= maxIdx; i++) {
      accMs += estimateDurationMs(queue[i].text, playbackRate: playbackRate);
      targetIdx = i;
      if (accMs >= targetBufferMs) {
        PlaybackLog.debug('Target reached at index $targetIdx (${(accMs/1000).toStringAsFixed(1)}s buffered)');
        break;
      }
    }

    final finalTarget = targetIdx.clamp(0, queue.length - 1);
    final segmentCount = finalTarget - currentIndex;
    PlaybackLog.debug('Target index: $finalTarget ($segmentCount segments ahead)');
    return finalTarget;
  }

  /// Suspend prefetch temporarily (e.g., during user interaction).
  void suspend({required void Function() onResume}) {
    _isSuspended = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(PlaybackConfig.prefetchResumeDelay, () {
      _isSuspended = false;
      onResume();
    });
  }

  /// Run prefetch loop.
  /// 
  /// [onSynthesisStarted] is called when synthesis begins for a segment.
  /// [onSynthesisComplete] is called when a segment is ready (cached or synthesized).
  /// These callbacks enable UI feedback for segment readiness.
  /// 
  /// H1: Uses cancellation token for immediate abort on context change.
  Future<void> runPrefetch({
    required RoutingEngine engine,
    required AudioCache cache,
    required List<AudioTrack> queue,
    required String voiceId,
    required double playbackRate,
    required int targetIndex,
    required bool Function() shouldContinue,
    void Function(int segmentIndex)? onSynthesisStarted,
    void Function(int segmentIndex)? onSynthesisComplete,
  }) async {
    // Guard: context must be initialized before prefetch
    if (_contextKey == _uninitializedContext) {
      PlaybackLog.warning('Prefetch called without context initialization, skipping');
      return;
    }
    
    // H1: Capture the current cancellation token
    final cancellationToken = _cancellationToken;
    
    PlaybackLog.progress('━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    PlaybackLog.progress('PREFETCH START');
    PlaybackLog.progress('Target index: $targetIndex');
    PlaybackLog.progress('Current prefetched through: $_prefetchedThroughIndex');
    PlaybackLog.progress('Voice: $voiceId, Rate: ${playbackRate}x');
    
    if (targetIndex <= _prefetchedThroughIndex) {
      PlaybackLog.progress('✓ Already prefetched to target, skipping');
      return;
    }
    if (_isRunning) {
      PlaybackLog.warning('Prefetch already running, skipping');
      return;
    }

    _isRunning = true;
    final startContext = _contextKey;
    final startTime = DateTime.now();
    int synthesized = 0;
    int cached = 0;
    int failed = 0;

    try {
      var i = _prefetchedThroughIndex + 1;
      PlaybackLog.progress('Starting from index $i');

      while (i <= targetIndex && i < queue.length) {
        // H1: Check cancellation token for immediate abort
        if (cancellationToken.isCancelled) {
          PlaybackLog.warning('Prefetch cancelled via token, aborting immediately');
          return;
        }
        
        if (!shouldContinue() || _contextKey != startContext) {
          PlaybackLog.warning('Context changed or should stop, aborting prefetch');
          return;
        }

        final track = queue[i];
        final wordCount = track.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        PlaybackLog.debug('[$i/${queue.length}] Prefetching: "${track.text.substring(0, track.text.length.clamp(0, 50))}..." ($wordCount words)');
        
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: track.text,
          playbackRate: CacheKeyGenerator.getSynthesisRate(playbackRate),
        );

        // Skip if already cached
        if (await cache.isReady(cacheKey)) {
          PlaybackLog.debug('✓ [$i] Already cached: $cacheKey');
          onSynthesisComplete?.call(i);  // Notify UI
          await _updatePrefetchedIndex(i);
          cached++;
          i++;
          continue;
        }
        
        // H1: Check cancellation again before expensive synthesis
        if (cancellationToken.isCancelled) {
          PlaybackLog.warning('Prefetch cancelled before synthesis, aborting');
          return;
        }

        // Synthesize
        PlaybackLog.debug('🔄 [$i] Synthesizing (not in cache)...');
        onSynthesisStarted?.call(i);  // Notify UI
        final synthStart = DateTime.now();
        try {
          await engine.synthesizeToWavFile(
            voiceId: voiceId,
            text: track.text,
            playbackRate: playbackRate,
          );
          
          // H1: Check cancellation after synthesis - discard result if cancelled
          if (cancellationToken.isCancelled) {
            PlaybackLog.warning('Prefetch cancelled during synthesis, discarding result');
            return;
          }
          
          final synthDuration = DateTime.now().difference(synthStart);
          PlaybackLog.debug('✓ [$i] Synthesized in ${synthDuration.inMilliseconds}ms');
          onSynthesisComplete?.call(i);  // Notify UI
          await _updatePrefetchedIndex(i);
          synthesized++;
        } catch (e, stackTrace) {
          final synthDuration = DateTime.now().difference(synthStart);
          PlaybackLog.error('[$i] Synthesis failed after ${synthDuration.inMilliseconds}ms: $e');
          PlaybackLog.error('Stack trace: $stackTrace');
          failed++;
          // Continue trying next tracks
        }

        i++;
      }
      
      final totalDuration = DateTime.now().difference(startTime);
      PlaybackLog.progress('━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      PlaybackLog.progress('PREFETCH COMPLETE');
      PlaybackLog.progress('Total time: ${totalDuration.inMilliseconds}ms');
      PlaybackLog.progress('Synthesized: $synthesized, Cached: $cached, Failed: $failed');
      PlaybackLog.progress('Final prefetched index: $_prefetchedThroughIndex');
      PlaybackLog.progress('━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } finally {
      _isRunning = false;
    }
  }

  /// Buffer until low watermark is reached (blocking).
  /// H1: Uses cancellation token for immediate abort on context change.
  Future<void> bufferUntilReady({
    required RoutingEngine engine,
    required List<AudioTrack> queue,
    required String voiceId,
    required double playbackRate,
    required int currentIndex,
    required bool Function() shouldContinue,
  }) async {
    if (queue.isEmpty || currentIndex < 0) return;
    
    // Guard: context must be initialized before buffering
    if (_contextKey == _uninitializedContext) {
      PlaybackLog.warning('BufferUntilReady called without context initialization, skipping');
      return;
    }
    
    // H1: Capture the current cancellation token
    final cancellationToken = _cancellationToken;

    var aheadMs = 0;
    var i = currentIndex;
    final startContext = _contextKey;

    while (i < queue.length && shouldContinue() && _contextKey == startContext) {
      // H1: Check cancellation token for immediate abort
      if (cancellationToken.isCancelled) {
        PlaybackLog.debug('BufferUntilReady cancelled via token');
        return;
      }
      
      final track = queue[i];

      try {
        await engine.synthesizeToWavFile(
          voiceId: voiceId,
          text: track.text,
          playbackRate: playbackRate,
        );
        
        // H1: Check cancellation after synthesis
        if (cancellationToken.isCancelled) {
          PlaybackLog.debug('BufferUntilReady cancelled during synthesis');
          return;
        }
        
        await _updatePrefetchedIndex(i);
      } catch (e) {
        // Continue trying
      }

      if (!shouldContinue()) return;

      if (i > currentIndex) {
        aheadMs += estimateDurationMs(track.text, playbackRate: playbackRate);
        if (aheadMs >= PlaybackConfig.lowWatermarkMs) break;
      }

      i++;
    }
  }

  /// Prefetch only the next segment with highest priority.
  ///
  /// This is called immediately when the current segment starts playing
  /// to ensure the next segment is always pre-synthesized before the
  /// current one finishes. This minimizes transition gaps.
  ///
  /// Unlike [runPrefetch], this:
  /// - Only targets currentIndex + 1
  /// - Bypasses watermark checks
  /// - Runs even if regular prefetch is already running
  /// - Does not block if the next segment is already being prefetched
  /// 
  /// H1: Uses cancellation token for immediate abort on context change.
  Future<void> prefetchNextSegmentImmediately({
    required RoutingEngine engine,
    required AudioCache cache,
    required List<AudioTrack> queue,
    required String voiceId,
    required double playbackRate,
    required int currentIndex,
    required bool Function() shouldContinue,
    void Function(int segmentIndex)? onSynthesisStarted,
    void Function(int segmentIndex)? onSynthesisComplete,
  }) async {
    // Guard: context must be initialized
    if (_contextKey == _uninitializedContext) {
      PlaybackLog.debug('Immediate prefetch called without context, skipping');
      return;
    }
    
    // H1: Capture the current cancellation token
    final cancellationToken = _cancellationToken;
    
    final nextIndex = currentIndex + 1;
    
    // No next segment
    if (nextIndex >= queue.length) {
      PlaybackLog.debug('No next segment to prefetch (at end of queue)');
      return;
    }
    
    // Already prefetched
    if (_prefetchedThroughIndex >= nextIndex) {
      PlaybackLog.debug('Next segment [$nextIndex] already prefetched');
      return;
    }
    
    final track = queue[nextIndex];
    final cacheKey = CacheKeyGenerator.generate(
      voiceId: voiceId,
      text: track.text,
      playbackRate: CacheKeyGenerator.getSynthesisRate(playbackRate),
    );
    
    // Already cached
    if (await cache.isReady(cacheKey)) {
      PlaybackLog.debug('Next segment [$nextIndex] already cached');
      onSynthesisComplete?.call(nextIndex);
      // Update index atomically
      await _updatePrefetchedIndex(nextIndex);
      return;
    }
    
    // H1: Check cancellation before expensive operations
    if (cancellationToken.isCancelled) {
      PlaybackLog.debug('Priority prefetch cancelled before synthesis');
      return;
    }
    
    // Need to synthesize - only if regular prefetch isn't already handling it
    // We don't want duplicate synthesis of the same segment
    if (_isRunning && _prefetchedThroughIndex >= currentIndex) {
      // Prefetch is running and will handle this segment
      PlaybackLog.debug('Regular prefetch will handle next segment');
      return;
    }
    
    if (!shouldContinue()) return;
    
    PlaybackLog.info('🚀 Priority prefetch: synthesizing next segment [$nextIndex]');
    onSynthesisStarted?.call(nextIndex);
    
    try {
      final synthStart = DateTime.now();
      await engine.synthesizeToWavFile(
        voiceId: voiceId,
        text: track.text,
        playbackRate: playbackRate,
      );
      
      // H1: Check cancellation after synthesis - discard result if cancelled
      if (cancellationToken.isCancelled) {
        PlaybackLog.debug('Priority prefetch cancelled during synthesis, discarding result');
        return;
      }
      
      final synthDuration = DateTime.now().difference(synthStart);
      PlaybackLog.info('✓ Priority prefetch complete [$nextIndex] in ${synthDuration.inMilliseconds}ms');
      onSynthesisComplete?.call(nextIndex);
      
      // Update prefetched index atomically
      await _updatePrefetchedIndex(nextIndex);
    } catch (e) {
      PlaybackLog.error('Priority prefetch failed for segment [$nextIndex]: $e');
      // Don't fail silently - regular prefetch may retry
    }
  }
}
