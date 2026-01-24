import 'dart:async';
import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import '../playback_config.dart';
import '../playback_log.dart';
import 'memory_monitor.dart';
import 'semaphore.dart';

/// Result of a synthesis operation.
class SynthesisResult {
  const SynthesisResult._({
    required this.segmentIndex,
    required this.isSuccess,
    this.cacheKey,
    this.durationMs,
    this.synthesisTimeMs,
    this.error,
  });

  /// Successful synthesis result.
  factory SynthesisResult.success({
    required int segmentIndex,
    required String cacheKey,
    required int durationMs,
    required int synthesisTimeMs,
  }) {
    return SynthesisResult._(
      segmentIndex: segmentIndex,
      isSuccess: true,
      cacheKey: cacheKey,
      durationMs: durationMs,
      synthesisTimeMs: synthesisTimeMs,
    );
  }

  /// Failed synthesis result.
  factory SynthesisResult.error(int segmentIndex, Object error) {
    return SynthesisResult._(
      segmentIndex: segmentIndex,
      isSuccess: false,
      error: error,
    );
  }

  final int segmentIndex;
  final bool isSuccess;
  final String? cacheKey;
  final int? durationMs;
  final int? synthesisTimeMs;
  final Object? error;

  /// Real-time factor: synthesis_time / audio_duration.
  /// < 1.0 means faster than real-time.
  double? get rtf {
    if (synthesisTimeMs == null || durationMs == null || durationMs == 0) {
      return null;
    }
    return synthesisTimeMs! / durationMs!;
  }
}

/// Orchestrates parallel synthesis operations with memory safety.
///
/// Uses a semaphore to limit concurrent operations and monitors memory
/// to prevent OOM conditions. Results stream to cache immediately.
class ParallelSynthesisOrchestrator {
  ParallelSynthesisOrchestrator({
    required int maxConcurrency,
    required MemoryMonitor memoryMonitor,
    int? memoryThresholdBytes,
  })  : _maxConcurrency = maxConcurrency.clamp(1, 4),
        _memoryMonitor = memoryMonitor,
        _memoryThresholdBytes =
            memoryThresholdBytes ?? PlatformMemoryMonitor.defaultThresholdBytes,
        _semaphore = Semaphore(maxConcurrency.clamp(1, 4));

  final int _maxConcurrency;
  final MemoryMonitor _memoryMonitor;
  final int _memoryThresholdBytes;
  final Semaphore _semaphore;

  /// Track in-flight synthesis operations.
  final Set<int> _inFlightIndices = {};

  /// Whether parallel synthesis is enabled (can be disabled at runtime).
  bool enabled = true;

  int get maxConcurrency => _maxConcurrency;
  int get activeCount => _inFlightIndices.length;
  bool get hasCapacity => _semaphore.hasAvailable;

  /// Synthesize multiple segments with controlled parallelism.
  ///
  /// If [enabled] is false or [maxConcurrency] is 1, uses sequential synthesis.
  /// Memory is checked before each synthesis starts.
  /// Results stream to [onResult] as they complete (out of order if parallel).
  Future<List<SynthesisResult>> synthesizeSegments({
    required List<AudioTrack> tracks,
    required RoutingEngine engine,
    required AudioCache cache,
    required String voiceId,
    required double playbackRate,
    void Function(SynthesisResult result)? onResult,
    bool Function()? shouldContinue,
  }) async {
    if (tracks.isEmpty) return [];

    // Use sequential if disabled or concurrency is 1
    if (!enabled || _maxConcurrency == 1) {
      return _synthesizeSequential(
        tracks: tracks,
        engine: engine,
        cache: cache,
        voiceId: voiceId,
        playbackRate: playbackRate,
        onResult: onResult,
        shouldContinue: shouldContinue,
      );
    }

    return _synthesizeParallel(
      tracks: tracks,
      engine: engine,
      cache: cache,
      voiceId: voiceId,
      playbackRate: playbackRate,
      onResult: onResult,
      shouldContinue: shouldContinue,
    );
  }

  Future<List<SynthesisResult>> _synthesizeSequential({
    required List<AudioTrack> tracks,
    required RoutingEngine engine,
    required AudioCache cache,
    required String voiceId,
    required double playbackRate,
    void Function(SynthesisResult result)? onResult,
    bool Function()? shouldContinue,
  }) async {
    final results = <SynthesisResult>[];

    for (var i = 0; i < tracks.length; i++) {
      if (shouldContinue != null && !shouldContinue()) {
        PlaybackLog.debug('[ParallelOrchestrator] Sequential aborted at index $i');
        break;
      }

      final result = await _synthesizeOne(
        track: tracks[i],
        index: i,
        engine: engine,
        cache: cache,
        voiceId: voiceId,
        playbackRate: playbackRate,
      );
      results.add(result);
      onResult?.call(result);
    }

    return results;
  }

  Future<List<SynthesisResult>> _synthesizeParallel({
    required List<AudioTrack> tracks,
    required RoutingEngine engine,
    required AudioCache cache,
    required String voiceId,
    required double playbackRate,
    void Function(SynthesisResult result)? onResult,
    bool Function()? shouldContinue,
  }) async {
    final results = List<SynthesisResult?>.filled(tracks.length, null);
    var completedCount = 0;
    final completer = Completer<List<SynthesisResult>>();

    developer.log(
        '[ParallelOrchestrator] Starting parallel synthesis of ${tracks.length} segments (max: $_maxConcurrency)');

    // Fire off all synthesis tasks with semaphore control
    for (var i = 0; i < tracks.length; i++) {
      final index = i;

      // Check cancellation before starting each task
      if (shouldContinue != null && !shouldContinue()) {
        PlaybackLog.debug(
            '[ParallelOrchestrator] Aborted before starting index $index');
        // Complete remaining slots with cancellation
        for (var j = index; j < tracks.length; j++) {
          results[j] =
              SynthesisResult.error(j, 'Synthesis cancelled');
          completedCount++;
        }
        if (completedCount == tracks.length && !completer.isCompleted) {
          completer.complete(results.cast<SynthesisResult>());
        }
        break;
      }

      // Launch synthesis with semaphore
      unawaited(_synthesizeWithSemaphore(
        track: tracks[index],
        index: index,
        engine: engine,
        cache: cache,
        voiceId: voiceId,
        playbackRate: playbackRate,
        shouldContinue: shouldContinue,
      ).then((result) {
        results[index] = result;
        completedCount++;
        onResult?.call(result);

        if (completedCount == tracks.length && !completer.isCompleted) {
          completer.complete(results.cast<SynthesisResult>());
        }
      }).catchError((Object error) {
        results[index] = SynthesisResult.error(index, error);
        completedCount++;
        onResult?.call(results[index]!);

        if (completedCount == tracks.length && !completer.isCompleted) {
          completer.complete(results.cast<SynthesisResult>());
        }
      }));
    }

    // If all were cancelled synchronously
    if (completedCount == tracks.length && !completer.isCompleted) {
      completer.complete(results.cast<SynthesisResult>());
    }

    return completer.future;
  }

  Future<SynthesisResult> _synthesizeWithSemaphore({
    required AudioTrack track,
    required int index,
    required RoutingEngine engine,
    required AudioCache cache,
    required String voiceId,
    required double playbackRate,
    bool Function()? shouldContinue,
  }) async {
    // Wait for semaphore slot
    await _semaphore.acquire();
    _inFlightIndices.add(index);

    try {
      // Check memory before starting
      if (!await _memoryMonitor.hasSufficientMemory(_memoryThresholdBytes)) {
        developer.log(
            '[ParallelOrchestrator] Memory pressure detected for segment $index');

        // Wait for memory with timeout
        final memoryAvailable = await _waitForMemory(
          threshold: _memoryThresholdBytes,
          timeout: const Duration(seconds: 30),
          shouldContinue: shouldContinue,
        );

        if (!memoryAvailable) {
          return SynthesisResult.error(index, 'Insufficient memory for synthesis');
        }
      }

      // Check cancellation after memory wait
      if (shouldContinue != null && !shouldContinue()) {
        return SynthesisResult.error(index, 'Synthesis cancelled');
      }

      return await _synthesizeOne(
        track: track,
        index: index,
        engine: engine,
        cache: cache,
        voiceId: voiceId,
        playbackRate: playbackRate,
      );
    } finally {
      _inFlightIndices.remove(index);
      _semaphore.release();
    }
  }

  Future<SynthesisResult> _synthesizeOne({
    required AudioTrack track,
    required int index,
    required RoutingEngine engine,
    required AudioCache cache,
    required String voiceId,
    required double playbackRate,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Check if already cached
      final effectiveRate =
          PlaybackConfig.rateIndependentSynthesis ? 1.0 : playbackRate;
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: voiceId,
        text: track.text,
        playbackRate: CacheKeyGenerator.getSynthesisRate(effectiveRate),
      );

      if (await cache.isReady(cacheKey)) {
        stopwatch.stop();
        PlaybackLog.debug('[ParallelOrchestrator] [$index] Cache hit: $cacheKey');
        // Get duration from synthesis result if we had cached it, otherwise estimate
        final file = await cache.fileFor(cacheKey);
        final fileSize = await file.length();
        // Rough estimate: 24kHz, 16-bit mono = ~48KB per second
        final estimatedDurationMs = (fileSize / 48).round();
        return SynthesisResult.success(
          segmentIndex: index,
          cacheKey: cacheKey.toFilename(),
          durationMs: estimatedDurationMs,
          synthesisTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      // Synthesize
      PlaybackLog.debug('[ParallelOrchestrator] [$index] Synthesizing...');
      final result = await engine.synthesizeToWavFile(
        voiceId: voiceId,
        text: track.text,
        playbackRate: effectiveRate,
      );

      stopwatch.stop();

      PlaybackLog.debug(
          '[ParallelOrchestrator] ✓ [$index] Synthesized in ${stopwatch.elapsedMilliseconds}ms, duration: ${result.durationMs}ms');

      return SynthesisResult.success(
        segmentIndex: index,
        cacheKey: cacheKey.toFilename(),
        durationMs: result.durationMs,
        synthesisTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      PlaybackLog.error('[ParallelOrchestrator] [$index] Error: $e');
      return SynthesisResult.error(index, e);
    }
  }

  Future<bool> _waitForMemory({
    required int threshold,
    required Duration timeout,
    bool Function()? shouldContinue,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (shouldContinue != null && !shouldContinue()) {
        return false;
      }

      if (await _memoryMonitor.hasSufficientMemory(threshold)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return false;
  }
}
