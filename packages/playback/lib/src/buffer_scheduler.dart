import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import 'playback_config.dart';
import 'resource_monitor.dart';

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

  /// Whether prefetch is currently running.
  bool _isRunning = false;

  /// Index through which prefetch has completed.
  int _prefetchedThroughIndex = -1;

  /// Context key for invalidation on voice/book change.
  String? _contextKey;

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
  void reset() {
    _isRunning = false;
    _prefetchedThroughIndex = -1;
    _contextKey = null;
  }

  /// Dispose resources.
  void dispose() {
    _resumeTimer?.cancel();
  }

  /// Update context and return true if context changed.
  bool updateContext({
    required String bookId,
    required int chapterIndex,
    required String voiceId,
    required double playbackRate,
    required int currentIndex,
  }) {
    final key = '$bookId|$chapterIndex|$voiceId|${playbackRate.toStringAsFixed(2)}';
    if (_contextKey != key) {
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
    if (_resourceMonitor != null && !_resourceMonitor!.canPrefetch) {
      print('[BufferScheduler] Prefetch disabled due to low battery (mode: $synthesisMode)');
      return false;
    }
    
    if (_isSuspended) {
      print('[BufferScheduler] Prefetch suspended, not starting');
      return false;
    }
    if (_isRunning) {
      print('[BufferScheduler] Prefetch already running');
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
    
    print('[BufferScheduler] Buffer check: ${bufferedSec}s buffered (threshold: ${lowWaterSec}s), mode: $synthesisMode → ${shouldStart ? "START PREFETCH" : "no prefetch needed"}');
    
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
    
    print('[BufferScheduler] Calculating target index from current=$currentIndex (mode: $synthesisMode, maxTracks: $maxTracks)');
    
    var targetIdx = currentIndex + 1;
    var accMs = 0;
    final maxIdx = currentIndex + maxTracks;

    for (var i = currentIndex + 1; i < queue.length && i <= maxIdx; i++) {
      accMs += estimateDurationMs(queue[i].text, playbackRate: playbackRate);
      targetIdx = i;
      if (accMs >= targetBufferMs) {
        print('[BufferScheduler] Target reached at index $targetIdx (${(accMs/1000).toStringAsFixed(1)}s buffered)');
        break;
      }
    }

    final finalTarget = targetIdx.clamp(0, queue.length - 1);
    final segmentCount = finalTarget - currentIndex;
    print('[BufferScheduler] Target index: $finalTarget ($segmentCount segments ahead)');
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
    print('[BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('[BufferScheduler] PREFETCH START');
    print('[BufferScheduler] Target index: $targetIndex');
    print('[BufferScheduler] Current prefetched through: $_prefetchedThroughIndex');
    print('[BufferScheduler] Voice: $voiceId, Rate: ${playbackRate}x');
    
    if (targetIndex <= _prefetchedThroughIndex) {
      print('[BufferScheduler] ✓ Already prefetched to target, skipping');
      return;
    }
    if (_isRunning) {
      print('[BufferScheduler] ⚠ Prefetch already running, skipping');
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
      print('[BufferScheduler] Starting from index $i');

      while (i <= targetIndex && i < queue.length) {
        if (!shouldContinue() || _contextKey != startContext) {
          print('[BufferScheduler] ⚠ Context changed or should stop, aborting prefetch');
          return;
        }

        final track = queue[i];
        final wordCount = track.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        print('[BufferScheduler] [$i/${queue.length}] Prefetching: "${track.text.substring(0, track.text.length.clamp(0, 50))}..." ($wordCount words)');
        
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: track.text,
          playbackRate: CacheKeyGenerator.getSynthesisRate(playbackRate),
        );

        // Skip if already cached
        if (await cache.isReady(cacheKey)) {
          print('[BufferScheduler] ✓ [$i] Already cached: $cacheKey');
          onSynthesisComplete?.call(i);  // Notify UI
          _prefetchedThroughIndex = i;
          cached++;
          i++;
          continue;
        }

        // Synthesize
        print('[BufferScheduler] 🔄 [$i] Synthesizing (not in cache)...');
        onSynthesisStarted?.call(i);  // Notify UI
        final synthStart = DateTime.now();
        try {
          await engine.synthesizeToWavFile(
            voiceId: voiceId,
            text: track.text,
            playbackRate: playbackRate,
          );
          final synthDuration = DateTime.now().difference(synthStart);
          print('[BufferScheduler] ✓ [$i] Synthesized in ${synthDuration.inMilliseconds}ms');
          onSynthesisComplete?.call(i);  // Notify UI
          _prefetchedThroughIndex = i;
          synthesized++;
        } catch (e, stackTrace) {
          final synthDuration = DateTime.now().difference(synthStart);
          print('[BufferScheduler] ❌ [$i] Synthesis failed after ${synthDuration.inMilliseconds}ms: $e');
          print('[BufferScheduler] Stack trace: $stackTrace');
          failed++;
          // Continue trying next tracks
        }

        i++;
      }
      
      final totalDuration = DateTime.now().difference(startTime);
      print('[BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('[BufferScheduler] PREFETCH COMPLETE');
      print('[BufferScheduler] Total time: ${totalDuration.inMilliseconds}ms');
      print('[BufferScheduler] Synthesized: $synthesized, Cached: $cached, Failed: $failed');
      print('[BufferScheduler] Final prefetched index: $_prefetchedThroughIndex');
      print('[BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } finally {
      _isRunning = false;
    }
  }

  /// Buffer until low watermark is reached (blocking).
  Future<void> bufferUntilReady({
    required RoutingEngine engine,
    required List<AudioTrack> queue,
    required String voiceId,
    required double playbackRate,
    required int currentIndex,
    required bool Function() shouldContinue,
  }) async {
    if (queue.isEmpty || currentIndex < 0) return;

    var aheadMs = 0;
    var i = currentIndex;
    final startContext = _contextKey;

    while (i < queue.length && shouldContinue() && _contextKey == startContext) {
      final track = queue[i];

      try {
        await engine.synthesizeToWavFile(
          voiceId: voiceId,
          text: track.text,
          playbackRate: playbackRate,
        );
        _prefetchedThroughIndex = i;
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
}
