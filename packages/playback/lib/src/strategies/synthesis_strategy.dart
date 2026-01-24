import 'dart:developer' as developer;

/// Strategy interface for synthesis behavior.
///
/// Implementations define how synthesis decisions are made:
/// - When to start prefetching
/// - How many segments to synthesize
/// - When to stop and conserve resources
abstract class SynthesisStrategy {
  /// Human-readable name for logging/debugging.
  String get name;

  /// Number of segments to synthesize ahead of playback position.
  int get preSynthesizeCount;

  /// Maximum concurrent synthesis operations (if parallel enabled).
  int get maxConcurrency;

  /// Whether to continue prefetching given current buffer state.
  bool shouldContinuePrefetch({
    required int bufferedMs,
    required int remainingSegments,
    required double recentRtf,
    required bool isPlaying,
  });

  /// Called when a synthesis completes to update strategy state.
  void onSynthesisComplete({
    required int segmentIndex,
    required Duration synthesisTime,
    required Duration audioDuration,
  });

  /// Create a serializable representation for persistence.
  Map<String, dynamic> toJson();

  /// Create strategy from persisted data.
  factory SynthesisStrategy.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'adaptive' => AdaptiveSynthesisStrategy.fromJson(json),
      'aggressive' => AggressiveSynthesisStrategy.fromJson(json),
      'conservative' => ConservativeSynthesisStrategy.fromJson(json),
      _ => AdaptiveSynthesisStrategy(),
    };
  }

  /// Create strategy from SynthesisStrategyType enum.
  factory SynthesisStrategy.fromType(SynthesisStrategyType type) {
    return switch (type) {
      SynthesisStrategyType.adaptive => AdaptiveSynthesisStrategy(),
      SynthesisStrategyType.aggressive => AggressiveSynthesisStrategy(),
      SynthesisStrategyType.conservative => ConservativeSynthesisStrategy(),
    };
  }
}

/// Enum for strategy selection in config/UI.
enum SynthesisStrategyType {
  adaptive,
  aggressive,
  conservative;

  String get displayName => switch (this) {
        SynthesisStrategyType.adaptive => 'Adaptive',
        SynthesisStrategyType.aggressive => 'Aggressive',
        SynthesisStrategyType.conservative => 'Conservative',
      };

  String get description => switch (this) {
        SynthesisStrategyType.adaptive =>
          'Balances performance and resources based on device speed',
        SynthesisStrategyType.aggressive =>
          'Maximum prefetch for uninterrupted playback (uses more battery)',
        SynthesisStrategyType.conservative =>
          'Minimal prefetch to save battery',
      };
}

/// Default adaptive strategy that balances quality and resources.
///
/// This strategy dynamically adjusts based on observed RTF:
/// - Fast devices (RTF < 0.3): prefetch 5 segments ahead
/// - Normal devices (RTF 0.3-0.8): prefetch 3 segments ahead
/// - Slow devices (RTF > 0.8): prefetch 2 segments ahead
class AdaptiveSynthesisStrategy implements SynthesisStrategy {
  int _preSynthesizeCount;
  double _avgRtf;
  int _completedCount;

  AdaptiveSynthesisStrategy({
    int preSynthesizeCount = 3,
    double avgRtf = 0.5,
    int completedCount = 0,
  })  : _preSynthesizeCount = preSynthesizeCount,
        _avgRtf = avgRtf,
        _completedCount = completedCount;

  @override
  String get name => 'Adaptive';

  @override
  int get preSynthesizeCount => _preSynthesizeCount;

  @override
  int get maxConcurrency => 1; // Sequential by default

  /// Current average RTF for debugging/monitoring.
  double get avgRtf => _avgRtf;

  /// Number of synthesis completions observed.
  int get completedCount => _completedCount;

  @override
  bool shouldContinuePrefetch({
    required int bufferedMs,
    required int remainingSegments,
    required double recentRtf,
    required bool isPlaying,
  }) {
    // Don't prefetch if not playing (unless buffer is dangerously low)
    if (!isPlaying && bufferedMs > 30000) return false;

    // Always maintain minimum buffer
    if (bufferedMs < 10000) return true;

    // If synthesis is fast (RTF < 0.5), be more aggressive
    final bufferThreshold = recentRtf < 0.5 ? 120000 : 60000;

    // Stop if we have enough buffer or no more segments
    if (bufferedMs >= bufferThreshold) return false;
    if (remainingSegments <= 0) return false;

    return true;
  }

  @override
  void onSynthesisComplete({
    required int segmentIndex,
    required Duration synthesisTime,
    required Duration audioDuration,
  }) {
    if (audioDuration.inMilliseconds <= 0) return;

    // Update running RTF average
    final rtf = synthesisTime.inMilliseconds / audioDuration.inMilliseconds;
    _completedCount++;
    _avgRtf = (_avgRtf * (_completedCount - 1) + rtf) / _completedCount;

    // Dynamically adjust preSynthesizeCount based on observed RTF
    if (_completedCount >= 5) {
      final oldCount = _preSynthesizeCount;
      if (_avgRtf < 0.3) {
        _preSynthesizeCount = 5; // Fast device - synthesize more ahead
      } else if (_avgRtf > 0.8) {
        _preSynthesizeCount = 2; // Slow device - be conservative
      } else {
        _preSynthesizeCount = 3; // Normal
      }
      if (oldCount != _preSynthesizeCount) {
        developer.log(
          '[STRATEGY] Adaptive: adjusted preSynthesizeCount $oldCount → $_preSynthesizeCount (avgRtf: ${_avgRtf.toStringAsFixed(2)})',
        );
      }
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'adaptive',
        'preSynthesizeCount': _preSynthesizeCount,
        'avgRtf': _avgRtf,
        'completedCount': _completedCount,
      };

  factory AdaptiveSynthesisStrategy.fromJson(Map<String, dynamic> json) {
    return AdaptiveSynthesisStrategy(
      preSynthesizeCount: json['preSynthesizeCount'] as int? ?? 3,
      avgRtf: (json['avgRtf'] as num?)?.toDouble() ?? 0.5,
      completedCount: json['completedCount'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'AdaptiveSynthesisStrategy(prefetch: $_preSynthesizeCount, avgRtf: ${_avgRtf.toStringAsFixed(2)}, completed: $_completedCount)';
}

/// Aggressive strategy for fast devices or when connected to power.
///
/// Always prefetches up to 5 minutes of audio regardless of RTF.
/// May use parallel synthesis if supported.
class AggressiveSynthesisStrategy implements SynthesisStrategy {
  const AggressiveSynthesisStrategy();

  @override
  String get name => 'Aggressive';

  @override
  int get preSynthesizeCount => 10;

  @override
  int get maxConcurrency => 2; // Allow parallel synthesis

  @override
  bool shouldContinuePrefetch({
    required int bufferedMs,
    required int remainingSegments,
    required double recentRtf,
    required bool isPlaying,
  }) {
    // Always prefetch if there's work to do (5 min buffer)
    return remainingSegments > 0 && bufferedMs < 300000;
  }

  @override
  void onSynthesisComplete({
    required int segmentIndex,
    required Duration synthesisTime,
    required Duration audioDuration,
  }) {
    // No dynamic adjustment - always aggressive
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'aggressive'};

  factory AggressiveSynthesisStrategy.fromJson(Map<String, dynamic> json) =>
      AggressiveSynthesisStrategy();

  @override
  String toString() => 'AggressiveSynthesisStrategy(prefetch: $preSynthesizeCount)';
}

/// Conservative strategy for battery saving.
///
/// Only prefetches when buffer is critically low and actively playing.
/// Single-threaded synthesis only.
class ConservativeSynthesisStrategy implements SynthesisStrategy {
  const ConservativeSynthesisStrategy();

  @override
  String get name => 'Conservative';

  @override
  int get preSynthesizeCount => 1;

  @override
  int get maxConcurrency => 1;

  @override
  bool shouldContinuePrefetch({
    required int bufferedMs,
    required int remainingSegments,
    required double recentRtf,
    required bool isPlaying,
  }) {
    // Only prefetch when buffer is critically low and playing
    return isPlaying && bufferedMs < 15000 && remainingSegments > 0;
  }

  @override
  void onSynthesisComplete({
    required int segmentIndex,
    required Duration synthesisTime,
    required Duration audioDuration,
  }) {
    // No tracking needed
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'conservative'};

  factory ConservativeSynthesisStrategy.fromJson(Map<String, dynamic> json) =>
      ConservativeSynthesisStrategy();

  @override
  String toString() => 'ConservativeSynthesisStrategy(prefetch: $preSynthesizeCount)';
}
