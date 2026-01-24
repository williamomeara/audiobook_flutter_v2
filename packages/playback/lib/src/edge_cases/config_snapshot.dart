import 'dart:developer' as developer;

/// A snapshot of configuration at a point in time for rollback purposes.
class ConfigSnapshot {
  ConfigSnapshot({
    required this.prefetchConcurrency,
    required this.parallelSynthesisEnabled,
    required this.bufferTargetMs,
    required this.timestamp,
    required this.reason,
  });

  /// Parallel synthesis concurrency (1-4).
  final int prefetchConcurrency;
  
  /// Whether parallel synthesis is enabled.
  final bool parallelSynthesisEnabled;
  
  /// Buffer target in milliseconds.
  final int bufferTargetMs;
  
  /// When this snapshot was taken.
  final DateTime timestamp;
  
  /// Why this snapshot was taken (e.g., "pre-calibration", "manual change").
  final String reason;

  Map<String, dynamic> toJson() => {
    'prefetchConcurrency': prefetchConcurrency,
    'parallelSynthesisEnabled': parallelSynthesisEnabled,
    'bufferTargetMs': bufferTargetMs,
    'timestamp': timestamp.toIso8601String(),
    'reason': reason,
  };

  factory ConfigSnapshot.fromJson(Map<String, dynamic> json) => ConfigSnapshot(
    prefetchConcurrency: json['prefetchConcurrency'] as int? ?? 2,
    parallelSynthesisEnabled: json['parallelSynthesisEnabled'] as bool? ?? true,
    bufferTargetMs: json['bufferTargetMs'] as int? ?? 30000,
    timestamp: json['timestamp'] != null 
        ? DateTime.parse(json['timestamp'] as String)
        : DateTime.now(),
    reason: json['reason'] as String? ?? 'unknown',
  );

  @override
  String toString() => 'ConfigSnapshot(concurrency=$prefetchConcurrency, '
      'parallel=$parallelSynthesisEnabled, buffer=${bufferTargetMs}ms, '
      'reason=$reason, time=$timestamp)';
}

/// Performance metrics used to evaluate if a rollback is needed.
class PerformanceMetrics {
  PerformanceMetrics({
    required this.bufferUnderrunCount,
    required this.synthesisFailureCount,
    required this.avgSynthesisTimeMs,
    required this.measurementPeriodMs,
  });

  /// Number of buffer underruns (playback gaps) during measurement period.
  final int bufferUnderrunCount;
  
  /// Number of synthesis failures during measurement period.
  final int synthesisFailureCount;
  
  /// Average synthesis time in milliseconds.
  final double avgSynthesisTimeMs;
  
  /// Duration of measurement period in milliseconds.
  final int measurementPeriodMs;

  /// Buffer underrun rate (underruns per hour).
  double get bufferUnderrunRate {
    if (measurementPeriodMs <= 0) return 0;
    final hoursElapsed = measurementPeriodMs / (1000 * 60 * 60);
    return bufferUnderrunCount / hoursElapsed;
  }

  /// Synthesis failure rate (failures per synthesis).
  double get synthesisFailureRate {
    // Estimate total syntheses from avg time and measurement period
    // This is approximate but useful for comparison
    if (avgSynthesisTimeMs <= 0 || measurementPeriodMs <= 0) return 0;
    final estimatedSyntheses = measurementPeriodMs / avgSynthesisTimeMs;
    if (estimatedSyntheses <= 0) return 0;
    return synthesisFailureCount / estimatedSyntheses;
  }

  @override
  String toString() => 'PerformanceMetrics('
      'underruns=$bufferUnderrunCount (${bufferUnderrunRate.toStringAsFixed(1)}/hr), '
      'failures=$synthesisFailureCount (${(synthesisFailureRate * 100).toStringAsFixed(1)}%), '
      'avgSynthesis=${avgSynthesisTimeMs.toStringAsFixed(0)}ms, '
      'period=${measurementPeriodMs}ms)';
}
