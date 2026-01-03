import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import 'playback_config.dart';

/// Manages audio prefetching for smooth playback.
///
/// The buffer scheduler decides which segments should be synthesized
/// ahead of the current playback position to maintain a smooth
/// listening experience.
class BufferScheduler {
  BufferScheduler();

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
  bool shouldPrefetch({
    required List<AudioTrack> queue,
    required int currentIndex,
    required double playbackRate,
  }) {
    if (_isSuspended) return false;
    if (_isRunning) return false;

    final bufferedMs = estimateBufferedAheadMs(
      queue: queue,
      currentIndex: currentIndex,
      playbackRate: playbackRate,
    );

    return bufferedMs < PlaybackConfig.lowWatermarkMs;
  }

  /// Calculate target prefetch index.
  int calculateTargetIndex({
    required List<AudioTrack> queue,
    required int currentIndex,
    required double playbackRate,
  }) {
    var targetIdx = currentIndex + 1;
    var accMs = 0;
    final maxIdx = currentIndex + PlaybackConfig.maxPrefetchTracks;

    for (var i = currentIndex + 1; i < queue.length && i <= maxIdx; i++) {
      accMs += estimateDurationMs(queue[i].text, playbackRate: playbackRate);
      targetIdx = i;
      if (accMs >= PlaybackConfig.bufferTargetMs) break;
    }

    return targetIdx.clamp(0, queue.length - 1);
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
  Future<void> runPrefetch({
    required RoutingEngine engine,
    required AudioCache cache,
    required List<AudioTrack> queue,
    required String voiceId,
    required double playbackRate,
    required int targetIndex,
    required bool Function() shouldContinue,
  }) async {
    if (targetIndex <= _prefetchedThroughIndex) return;
    if (_isRunning) return;

    _isRunning = true;
    final startContext = _contextKey;

    try {
      var i = _prefetchedThroughIndex + 1;

      while (i <= targetIndex && i < queue.length) {
        if (!shouldContinue() || _contextKey != startContext) return;

        final track = queue[i];
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: track.text,
          playbackRate: CacheKeyGenerator.getSynthesisRate(playbackRate),
        );

        // Skip if already cached
        if (await cache.isReady(cacheKey)) {
          _prefetchedThroughIndex = i;
          i++;
          continue;
        }

        // Synthesize
        try {
          await engine.synthesizeToWavFile(
            voiceId: voiceId,
            text: track.text,
            playbackRate: playbackRate,
          );
          _prefetchedThroughIndex = i;
        } catch (e) {
          // Log error but continue trying
        }

        i++;
      }
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
