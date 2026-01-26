import 'dart:math' as math;

/// Sample of RTF data with context.
class RTFSample {
  /// The raw RTF value (synthesis_time / audio_duration).
  final double rtf;

  /// Concurrency level when this sample was taken.
  final int concurrency;

  /// Timestamp when recorded.
  final DateTime timestamp;

  /// Engine type that produced this sample.
  final String engineType;

  /// Voice ID that produced this sample.
  final String voiceId;

  const RTFSample({
    required this.rtf,
    required this.concurrency,
    required this.timestamp,
    required this.engineType,
    required this.voiceId,
  });

  Map<String, dynamic> toJson() => {
        'rtf': rtf,
        'concurrency': concurrency,
        'timestamp': timestamp.toIso8601String(),
        'engineType': engineType,
        'voiceId': voiceId,
      };
}

/// Statistics computed from RTF samples.
class RTFStatistics {
  /// Mean RTF across samples.
  final double mean;

  /// Median RTF (P50).
  final double median;

  /// 90th percentile RTF.
  final double p90;

  /// 95th percentile RTF (worst-case typical).
  final double p95;

  /// Minimum RTF observed.
  final double min;

  /// Maximum RTF observed.
  final double max;

  /// Standard deviation (variance indicator).
  final double standardDeviation;

  /// Number of samples in the calculation.
  final int sampleCount;

  const RTFStatistics({
    required this.mean,
    required this.median,
    required this.p90,
    required this.p95,
    required this.min,
    required this.max,
    required this.standardDeviation,
    required this.sampleCount,
  });

  /// Coefficient of variation (stdDev / mean).
  /// Higher values indicate less stable performance.
  double get coefficientOfVariation => mean > 0 ? standardDeviation / mean : 0;

  /// Whether performance is stable (CV < 0.2 = 20%).
  bool get isStable => coefficientOfVariation < 0.2;

  /// Whether this device can likely maintain realtime playback.
  /// Uses P95 with safety margin.
  bool canMaintainRealtime(double playbackRate) {
    // Need effective RTF < 1/playbackRate
    // At 1.5x, need RTF < 0.67
    // Add 20% safety margin
    final required = (1.0 / playbackRate) * 0.8;
    return p95 < required;
  }

  /// Maximum sustainable playback rate.
  double get maxSustainableRate {
    if (p95 <= 0) return 3.0; // Unknown, assume good
    return (1.0 / p95) * 0.8; // With 20% margin
  }

  Map<String, dynamic> toJson() => {
        'mean': mean.toStringAsFixed(3),
        'median': median.toStringAsFixed(3),
        'p90': p90.toStringAsFixed(3),
        'p95': p95.toStringAsFixed(3),
        'min': min.toStringAsFixed(3),
        'max': max.toStringAsFixed(3),
        'stdDev': standardDeviation.toStringAsFixed(3),
        'cv': coefficientOfVariation.toStringAsFixed(3),
        'isStable': isStable,
        'sampleCount': sampleCount,
      };

  static RTFStatistics empty = const RTFStatistics(
    mean: 0,
    median: 0,
    p90: 0,
    p95: 0,
    min: 0,
    max: 0,
    standardDeviation: 0,
    sampleCount: 0,
  );
}

/// Monitors Real-Time Factor (RTF) for synthesis performance tracking.
///
/// Maintains a rolling window of RTF samples and computes statistics.
/// Used by [PerformanceAdvisor] to make recommendations.
///
/// ## Best Practices Applied
///
/// - Rolling window of 50-100 samples (smooths anomalies)
/// - Track mean, median, P90, P95 (captures worst-case)
/// - Standard deviation for stability assessment
/// - Per-engine/voice tracking capability
///
/// ## Example
/// ```dart
/// final monitor = RTFMonitor(windowSize: 50);
///
/// // Record synthesis completion
/// monitor.recordSynthesis(
///   audioDuration: Duration(seconds: 10),
///   synthesisTime: Duration(milliseconds: 3500),
///   concurrency: 2,
///   engineType: 'kokoro',
///   voiceId: 'kokoro_af_bella',
/// );
///
/// // Get statistics
/// final stats = monitor.statistics;
/// print('Mean RTF: ${stats.mean}');
/// ```
class RTFMonitor {
  /// Maximum samples to keep in rolling window.
  final int windowSize;

  /// Internal sample storage.
  final List<RTFSample> _samples = [];

  /// Create monitor with specified window size.
  RTFMonitor({this.windowSize = 50});

  /// Number of samples currently tracked.
  int get sampleCount => _samples.length;

  /// Whether enough samples exist for reliable statistics.
  /// Typically need 10+ samples for meaningful data.
  bool get hasReliableData => _samples.length >= 10;

  /// Record a new synthesis sample.
  ///
  /// [audioDuration] is how long the audio plays.
  /// [synthesisTime] is how long synthesis took.
  void recordSynthesis({
    required Duration audioDuration,
    required Duration synthesisTime,
    required int concurrency,
    required String engineType,
    required String voiceId,
  }) {
    if (audioDuration.inMilliseconds <= 0) return;

    final rtf = synthesisTime.inMilliseconds / audioDuration.inMilliseconds;

    _samples.add(RTFSample(
      rtf: rtf,
      concurrency: concurrency,
      timestamp: DateTime.now(),
      engineType: engineType,
      voiceId: voiceId,
    ));

    // Trim to window size
    while (_samples.length > windowSize) {
      _samples.removeAt(0);
    }
  }

  /// Get current RTF statistics across all samples.
  RTFStatistics get statistics {
    if (_samples.isEmpty) return RTFStatistics.empty;

    final rtfValues = _samples.map((s) => s.rtf).toList()..sort();
    final n = rtfValues.length;

    // Calculate mean
    final mean = rtfValues.reduce((a, b) => a + b) / n;

    // Calculate standard deviation
    final variance =
        rtfValues.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            n;
    final stdDev = math.sqrt(variance);

    return RTFStatistics(
      mean: mean,
      median: _percentile(rtfValues, 50),
      p90: _percentile(rtfValues, 90),
      p95: _percentile(rtfValues, 95),
      min: rtfValues.first,
      max: rtfValues.last,
      standardDeviation: stdDev,
      sampleCount: n,
    );
  }

  /// Get statistics filtered by engine type.
  RTFStatistics statisticsForEngine(String engineType) {
    final filtered =
        _samples.where((s) => s.engineType == engineType).toList();
    if (filtered.isEmpty) return RTFStatistics.empty;

    return _computeStats(filtered);
  }

  /// Get statistics filtered by voice ID.
  RTFStatistics statisticsForVoice(String voiceId) {
    final filtered = _samples.where((s) => s.voiceId == voiceId).toList();
    if (filtered.isEmpty) return RTFStatistics.empty;

    return _computeStats(filtered);
  }

  /// Get raw samples (for debugging/export).
  List<RTFSample> get samples => List.unmodifiable(_samples);

  /// Clear all samples.
  void clear() => _samples.clear();

  /// Get recent average RTF (last N samples).
  double recentAverageRTF({int count = 10}) {
    if (_samples.isEmpty) return 0;
    final recent = _samples.skip(math.max(0, _samples.length - count));
    return recent.map((s) => s.rtf).reduce((a, b) => a + b) / recent.length;
  }

  /// Effective RTF considering parallelism.
  /// 2 concurrent at RTF 0.8 ≈ effective 0.4 throughput per slot.
  double get effectiveRTF {
    if (_samples.isEmpty) return 0;
    final avgConcurrency =
        _samples.map((s) => s.concurrency).reduce((a, b) => a + b) /
            _samples.length;
    return statistics.mean / avgConcurrency;
  }

  RTFStatistics _computeStats(List<RTFSample> samples) {
    final rtfValues = samples.map((s) => s.rtf).toList()..sort();
    final n = rtfValues.length;

    final mean = rtfValues.reduce((a, b) => a + b) / n;
    final variance =
        rtfValues.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            n;
    final stdDev = math.sqrt(variance);

    return RTFStatistics(
      mean: mean,
      median: _percentile(rtfValues, 50),
      p90: _percentile(rtfValues, 90),
      p95: _percentile(rtfValues, 95),
      min: rtfValues.first,
      max: rtfValues.last,
      standardDeviation: stdDev,
      sampleCount: n,
    );
  }

  double _percentile(List<double> sorted, int percentile) {
    if (sorted.isEmpty) return 0;
    final index = (percentile / 100 * (sorted.length - 1)).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
