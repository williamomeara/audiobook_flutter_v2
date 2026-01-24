import 'dart:developer' as developer;

import 'synthesis_strategy.dart';

/// Manages synthesis strategy selection and auto-switching.
///
/// This class wraps a [SynthesisStrategy] and provides:
/// - Auto-selection based on device state (charging, low power, RTF)
/// - Strategy persistence via [toJson]/[fromJson]
/// - Strategy change notifications
class SynthesisStrategyManager {
  SynthesisStrategy _strategy;
  void Function(SynthesisStrategy)? _onStrategyChanged;

  SynthesisStrategyManager({
    SynthesisStrategy? strategy,
  }) : _strategy = strategy ?? AdaptiveSynthesisStrategy();

  /// Current active strategy.
  SynthesisStrategy get strategy => _strategy;

  /// The type of the current strategy.
  SynthesisStrategyType get strategyType => switch (_strategy) {
        AdaptiveSynthesisStrategy() => SynthesisStrategyType.adaptive,
        AggressiveSynthesisStrategy() => SynthesisStrategyType.aggressive,
        ConservativeSynthesisStrategy() => SynthesisStrategyType.conservative,
        _ => SynthesisStrategyType.adaptive,
      };

  /// Set callback for strategy changes.
  void setOnStrategyChanged(void Function(SynthesisStrategy)? callback) {
    _onStrategyChanged = callback;
  }

  /// Update strategy at runtime (e.g., when charging state changes).
  void setStrategy(SynthesisStrategy newStrategy) {
    if (_strategy.runtimeType == newStrategy.runtimeType) {
      // Same type, don't log or notify
      _strategy = newStrategy;
      return;
    }

    developer.log(
      '[STRATEGY] Strategy changed: ${_strategy.name} → ${newStrategy.name}',
    );
    _strategy = newStrategy;
    _onStrategyChanged?.call(newStrategy);
  }

  /// Set strategy by type.
  void setStrategyType(SynthesisStrategyType type) {
    setStrategy(SynthesisStrategy.fromType(type));
  }

  /// Auto-select strategy based on device state.
  ///
  /// Priority:
  /// 1. Low power mode → Conservative
  /// 2. Charging + fast device → Aggressive
  /// 3. Otherwise → Adaptive
  void autoSelectStrategy({
    required bool isCharging,
    required bool isLowPowerMode,
    required double measuredRtf,
  }) {
    if (isLowPowerMode) {
      developer.log('[STRATEGY] Auto-select: Low power mode → Conservative');
      setStrategy(ConservativeSynthesisStrategy());
    } else if (isCharging && measuredRtf < 0.5) {
      developer.log('[STRATEGY] Auto-select: Charging + fast RTF → Aggressive');
      setStrategy(AggressiveSynthesisStrategy());
    } else {
      // For adaptive, preserve learned state if already adaptive
      if (_strategy is AdaptiveSynthesisStrategy) {
        developer.log('[STRATEGY] Auto-select: Keeping current Adaptive');
        return;
      }
      developer.log('[STRATEGY] Auto-select: Default → Adaptive');
      setStrategy(AdaptiveSynthesisStrategy());
    }
  }

  /// Forward shouldContinuePrefetch to current strategy.
  bool shouldContinuePrefetch({
    required int bufferedMs,
    required int remainingSegments,
    required double recentRtf,
    required bool isPlaying,
  }) {
    return _strategy.shouldContinuePrefetch(
      bufferedMs: bufferedMs,
      remainingSegments: remainingSegments,
      recentRtf: recentRtf,
      isPlaying: isPlaying,
    );
  }

  /// Forward onSynthesisComplete to current strategy.
  void onSynthesisComplete({
    required int segmentIndex,
    required Duration synthesisTime,
    required Duration audioDuration,
  }) {
    _strategy.onSynthesisComplete(
      segmentIndex: segmentIndex,
      synthesisTime: synthesisTime,
      audioDuration: audioDuration,
    );
  }

  /// Create from JSON.
  factory SynthesisStrategyManager.fromJson(Map<String, dynamic> json) {
    return SynthesisStrategyManager(
      strategy: SynthesisStrategy.fromJson(json),
    );
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => _strategy.toJson();

  @override
  String toString() => 'SynthesisStrategyManager($_strategy)';
}
