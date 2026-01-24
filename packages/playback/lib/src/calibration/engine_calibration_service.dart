import 'dart:async';
import 'dart:developer' as developer;

import 'package:tts_engines/tts_engines.dart';
import 'package:core_domain/core_domain.dart';
import '../synthesis/semaphore.dart';

/// Result of a calibration run for a specific engine/voice.
class CalibrationResult {
  /// Optimal concurrency level (1-4).
  final int optimalConcurrency;

  /// Expected speedup factor vs sequential (e.g., 1.65 means 65% faster).
  final double expectedSpeedup;

  /// Measured real-time factor at optimal concurrency.
  final double rtfAtOptimal;

  /// Whether there were warnings (e.g., high failure rate at higher concurrency).
  final bool hasWarnings;

  /// Warning message if any.
  final String? warningMessage;

  /// Duration of calibration in milliseconds.
  final int calibrationDurationMs;

  /// Detailed results for each concurrency level tested.
  final Map<int, ConcurrencyTestResult> testResults;

  CalibrationResult({
    required this.optimalConcurrency,
    required this.expectedSpeedup,
    required this.rtfAtOptimal,
    required this.hasWarnings,
    this.warningMessage,
    required this.calibrationDurationMs,
    required this.testResults,
  });

  @override
  String toString() {
    return 'CalibrationResult(optimal=$optimalConcurrency, speedup=${expectedSpeedup.toStringAsFixed(2)}x, rtf=${rtfAtOptimal.toStringAsFixed(2)})';
  }
}

/// Result for a single concurrency level test.
class ConcurrencyTestResult {
  final int concurrency;
  final int totalTimeMs;
  final int segmentsCompleted;
  final int segmentsFailed;
  final double audioDurationSeconds;
  final double rtf;

  ConcurrencyTestResult({
    required this.concurrency,
    required this.totalTimeMs,
    required this.segmentsCompleted,
    required this.segmentsFailed,
    required this.audioDurationSeconds,
    required this.rtf,
  });

  double get failureRate =>
      segmentsCompleted + segmentsFailed > 0
          ? segmentsFailed / (segmentsCompleted + segmentsFailed)
          : 0;
}

/// Callback for calibration progress updates.
typedef CalibrationProgressCallback = void Function(
  int currentStep,
  int totalSteps,
  String message,
);

/// Service to calibrate TTS engine performance and find optimal concurrency.
class EngineCalibrationService {
  /// Test sentences for calibration (longer for better accuracy).
  /// Using 10 sentences for more reliable measurements.
  static const _calibrationText = '''
The quick brown fox jumps over the lazy dog. This is a test of synthesis speed.
How vexingly quick daft zebras jump! Pack my box with five dozen liquor jugs.
Sphinx of black quartz, judge my vow. The five boxing wizards jump quickly.
Two driven jocks help fax my big quiz. The job requires extra pluck and zeal.
Crazy Frederick bought many very exquisite opal jewels. We promptly judged antique ivory.
Waltz, nymph, for quick jigs vex Bud. Quick zephyrs blow, vexing daft Jim.
The wizard quickly jinxed the gnomes before they vaporized. Grumpy wizards make toxic brew.
All questions asked by five watched experts amaze the judge. Jack quietly moved up front.
Big July earthquakes confound zany experimental vow. Foxy parsons quiz and cajole lovably.
Sixty zippers were quickly picked from the woven jute bag. My faxed joke won a pager.
''';

  /// Run quick calibration for an engine/voice combination.
  ///
  /// Tests concurrency levels 1, 2, 3 with short segments to find optimal.
  /// Takes approximately 30-60 seconds depending on device.
  ///
  /// [routingEngine] - The TTS routing engine to use.
  /// [voiceId] - The voice to calibrate.
  /// [onProgress] - Optional callback for progress updates.
  /// [clearCacheFunc] - Function to clear audio cache between tests.
  ///
  /// Returns [CalibrationResult] with optimal settings.
  Future<CalibrationResult> calibrateEngine({
    required RoutingEngine routingEngine,
    required String voiceId,
    CalibrationProgressCallback? onProgress,
    Future<void> Function()? clearCacheFunc,
  }) async {
    final overallStart = DateTime.now();
    developer.log('[Calibration] Starting calibration for voice: $voiceId');

    // Segment the test text
    final segments = segmentText(_calibrationText);
    developer.log('[Calibration] Test segments: ${segments.length}');

    final testResults = <int, ConcurrencyTestResult>{};
    const concurrencyLevels = [1, 2, 3];

    // Test each concurrency level
    for (var i = 0; i < concurrencyLevels.length; i++) {
      final concurrency = concurrencyLevels[i];
      onProgress?.call(
        i + 1,
        concurrencyLevels.length,
        'Testing concurrency $concurrency...',
      );

      // Clear cache between tests for fair comparison
      if (clearCacheFunc != null) {
        await clearCacheFunc();
      }

      final result = await _testConcurrencyLevel(
        routingEngine: routingEngine,
        voiceId: voiceId,
        segments: segments,
        concurrency: concurrency,
      );

      testResults[concurrency] = result;

      developer.log(
        '[Calibration] Concurrency $concurrency: ${result.totalTimeMs}ms, '
        '${result.segmentsFailed} failed, RTF: ${result.rtf.toStringAsFixed(2)}',
      );
    }

    // Determine optimal concurrency
    final optimal = _determineOptimalConcurrency(testResults);

    final calibrationDuration =
        DateTime.now().difference(overallStart).inMilliseconds;

    // Calculate speedup vs sequential
    final sequentialTime = testResults[1]!.totalTimeMs;
    final optimalTime = testResults[optimal.concurrency]!.totalTimeMs;
    final speedup = sequentialTime / optimalTime;

    // Determine the reason for the choice
    String decisionReason;
    if (optimal.concurrency == 1 && testResults[1]!.rtf < 0.5) {
      decisionReason = 'Sequential chosen: RTF ${testResults[1]!.rtf.toStringAsFixed(2)} already fast enough (< 0.5)';
    } else if (optimal.concurrency > 1) {
      decisionReason = 'Parallel ${optimal.concurrency}x chosen: ${speedup.toStringAsFixed(2)}x speedup, RTF still > 0.5';
    } else {
      decisionReason = 'Sequential chosen: Parallelism showed insufficient benefit';
    }

    final result = CalibrationResult(
      optimalConcurrency: optimal.concurrency,
      expectedSpeedup: speedup,
      rtfAtOptimal: testResults[optimal.concurrency]!.rtf,
      hasWarnings: optimal.hasWarning,
      warningMessage: optimal.warningMessage,
      calibrationDurationMs: calibrationDuration,
      testResults: testResults,
    );

    // Log comprehensive summary via multiple channels for visibility
    final summary = '''
╔════════════════════════════════════════════════════════════════╗
║ CALIBRATION COMPLETE                                            ║
╠════════════════════════════════════════════════════════════════╣
║ Voice:    $voiceId
║ Segments: ${segments.length}
║ Duration: ${calibrationDuration}ms
╠────────────────────────────────────────────────────────────────╣
║ RESULTS BY CONCURRENCY LEVEL:
${testResults.entries.map((e) => '''║   Level ${e.key}: ${e.value.totalTimeMs}ms (${e.value.segmentsFailed} failed, RTF: ${e.value.rtf.toStringAsFixed(2)}x)''').join('\n')}
╠────────────────────────────────────────────────────────────────╣
║ DECISION: $decisionReason
║ OPTIMAL: ${optimal.concurrency}x parallel
║ SPEEDUP: ${speedup.toStringAsFixed(2)}x vs sequential
║ RTF:     ${result.rtfAtOptimal.toStringAsFixed(2)}x (synthesis/audio)
${optimal.hasWarning ? '║ WARNING: ${optimal.warningMessage}' : ''}
╚════════════════════════════════════════════════════════════════╝
''';

    // Output via multiple channels for visibility
    developer.log(summary, name: 'EngineCalibration');
    assert(() {
      // ignore: avoid_print
      print(summary);
      return true;
    }());

    return result;
  }

  /// Test a single concurrency level.
  Future<ConcurrencyTestResult> _testConcurrencyLevel({
    required RoutingEngine routingEngine,
    required String voiceId,
    required List<Segment> segments,
    required int concurrency,
  }) async {
    final startTime = DateTime.now();
    
    // Collect results in a thread-safe manner using a list with a lock
    // This avoids the race condition when multiple concurrent futures
    // try to update shared counters
    final results = <({double duration, bool success})>[];
    final resultLock = Semaphore(1);

    final semaphore = Semaphore(concurrency);
    final futures = <Future<void>>[];

    for (final segment in segments) {
      futures.add(() async {
        await semaphore.acquire();
        try {
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: segment.text,
            playbackRate: 1.0,
          );

          // Use the actual duration from synthesis result
          final audioDuration = result.durationMs / 1000.0;
          
          // Thread-safe result collection
          await resultLock.acquire();
          try {
            results.add((duration: audioDuration, success: true));
          } finally {
            resultLock.release();
          }
        } catch (e) {
          developer.log('[Calibration] Segment failed: $e');
          await resultLock.acquire();
          try {
            results.add((duration: 0.0, success: false));
          } finally {
            resultLock.release();
          }
        } finally {
          semaphore.release();
        }
      }());
    }

    await Future.wait(futures);

    // Aggregate results after all futures complete (now thread-safe)
    final completed = results.where((r) => r.success).length;
    final failed = results.where((r) => !r.success).length;
    final totalAudioDuration = results.fold(0.0, (sum, r) => sum + r.duration);

    final totalTime = DateTime.now().difference(startTime);
    final rtf =
        totalAudioDuration > 0
            ? totalTime.inMilliseconds / 1000 / totalAudioDuration
            : 0.0;

    return ConcurrencyTestResult(
      concurrency: concurrency,
      totalTimeMs: totalTime.inMilliseconds,
      segmentsCompleted: completed,
      segmentsFailed: failed,
      audioDurationSeconds: totalAudioDuration,
      rtf: rtf,
    );
  }

  /// Determine optimal concurrency from test results.
  /// 
  /// Selection criteria:
  /// 1. No failures (or very low failure rate < 10%)
  /// 2. Shows meaningful speedup (> 10% improvement vs baseline)
  /// 3. Incremental gain vs previous level is significant (> 5%)
  /// 4. **Resource efficiency**: If RTF is already well under 1.0, higher 
  ///    concurrency wastes resources for diminishing returns
  ({int concurrency, bool hasWarning, String? warningMessage})
  _determineOptimalConcurrency(Map<int, ConcurrencyTestResult> results) {
    int optimal = 1;
    String? warning;

    final baseline = results[1]!.totalTimeMs;
    final baselineRtf = results[1]!.rtf;
    int previousTime = baseline;

    developer.log(
      '[Calibration] Baseline RTF: ${baselineRtf.toStringAsFixed(2)}x',
    );

    // Resource efficiency threshold: if synthesis is already 2x faster than 
    // real-time (RTF < 0.5), parallelism is wasteful - we can generate audio 
    // faster than it plays back, so no need to burn extra resources
    const rtfThresholdForSequential = 0.5;
    
    // If baseline is already very fast, don't bother with parallel
    if (baselineRtf < rtfThresholdForSequential) {
      developer.log(
        '[Calibration] Baseline RTF ${baselineRtf.toStringAsFixed(2)} < $rtfThresholdForSequential - '
        'synthesis is already fast enough, recommending sequential to save resources',
      );
      return (
        concurrency: 1,
        hasWarning: false,
        warningMessage: null,
      );
    }

    for (final level in [2, 3]) {
      final result = results[level];
      if (result == null) continue;

      final failureRate = result.failureRate;
      final speedupVsBaseline = baseline / result.totalTimeMs;
      final speedupVsPrevious = previousTime / result.totalTimeMs;
      final rtfAtLevel = result.rtf;

      developer.log(
        '[Calibration] Level $level: ${result.totalTimeMs}ms, '
        'RTF: ${rtfAtLevel.toStringAsFixed(2)}x, '
        'speedup vs baseline: ${speedupVsBaseline.toStringAsFixed(2)}x, '
        'speedup vs previous: ${speedupVsPrevious.toStringAsFixed(2)}x, '
        'failures: ${(failureRate * 100).toStringAsFixed(0)}%',
      );

      // Skip if failure rate is too high
      if (failureRate > 0.1) {
        warning =
            'Concurrency $level had ${(failureRate * 100).toStringAsFixed(0)}% failures';
        break; // Don't try higher levels if this one failed
      }

      // Resource efficiency check: If current level already achieves RTF < 0.5,
      // there's no point going higher - we're generating audio faster than
      // it can be played back, wasting device resources (battery, heat, memory)
      if (rtfAtLevel < rtfThresholdForSequential && optimal > 1) {
        developer.log(
          '[Calibration] Level $level achieves RTF ${rtfAtLevel.toStringAsFixed(2)} < $rtfThresholdForSequential - '
          'sufficient performance reached, stopping at Level $optimal',
        );
        break;
      }

      // Only upgrade if:
      // 1. Meaningful speedup vs baseline (> 10%)
      // 2. Still getting incremental benefit vs previous level (> 5%)
      if (speedupVsBaseline > 1.1 && speedupVsPrevious > 1.05) {
        optimal = level;
        previousTime = result.totalTimeMs;
        
        // If this level already achieves good RTF, stop here
        if (rtfAtLevel < rtfThresholdForSequential) {
          developer.log(
            '[Calibration] Level $level achieves sufficient RTF ${rtfAtLevel.toStringAsFixed(2)}, '
            'no need for higher concurrency',
          );
          break;
        }
      } else {
        // Diminishing returns - stick with previous level
        developer.log(
          '[Calibration] Level $level shows diminishing returns, stopping at $optimal',
        );
        break;
      }
    }

    return (
      concurrency: optimal,
      hasWarning: warning != null,
      warningMessage: warning,
    );
  }
}
