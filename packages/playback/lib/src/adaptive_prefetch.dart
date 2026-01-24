import 'dart:math';

import 'playback_config.dart';
import 'playback_log.dart';

/// Memory pressure levels from the platform.
///
/// These correspond to Android's ComponentCallbacks2 trim levels.
enum MemoryPressure {
  /// No memory pressure.
  none,

  /// Moderate pressure - reduce memory usage if possible.
  moderate,

  /// Critical pressure - free as much memory as possible.
  critical,
}

/// Calculates optimal prefetch window based on runtime factors.
///
/// This replaces static prefetch window calculations with adaptive
/// logic that considers the current playback context.
///
/// All TTS synthesis is performed locally on-device using ONNX Runtime.
/// These calculations optimize local resource usage.
class AdaptivePrefetchConfig {
  AdaptivePrefetchConfig({
    PrefetchMode? prefetchMode,
  }) : _prefetchMode = prefetchMode ?? PrefetchMode.adaptive;

  final PrefetchMode _prefetchMode;

  /// Calculate the optimal number of segments to prefetch.
  ///
  /// Factors considered:
  /// - Queue length (don't overshoot)
  /// - Measured RTF (fast synthesis = can prefetch more)
  /// - Synthesis mode (quality vs performance)
  /// - Charging state (can be more aggressive when plugged in)
  /// - Memory pressure (reduce if low memory)
  ///
  /// Returns the number of segments to prefetch ahead of current position.
  int calculatePrefetchWindow({
    required int queueLength,
    required int currentPosition,
    required double measuredRTF,
    required SynthesisMode synthesisMode,
    required bool isCharging,
    required MemoryPressure memoryPressure,
  }) {
    // Honor user's explicit mode choice
    if (_prefetchMode == PrefetchMode.off) return 0;
    if (_prefetchMode == PrefetchMode.conservative) {
      return min(2, queueLength - currentPosition);
    }

    // Calculate remaining segments
    final remainingSegments = queueLength - currentPosition;
    if (remainingSegments <= 0) return 0;

    // Base prefetch from synthesis mode (battery-aware)
    int baseSegments = synthesisMode.maxPrefetchTracks;

    // Aggressive mode: 1.5x base
    if (_prefetchMode == PrefetchMode.aggressive) {
      baseSegments = (baseSegments * 1.5).round();
    }

    // RTF adjustment: if synthesis is fast, prefetch more
    // RTF < 0.3 means synthesis is 3x faster than playback
    double rtfMultiplier = 1.0;
    if (measuredRTF > 0) {
      // Only adjust if we have valid RTF data
      if (measuredRTF < 0.3) {
        rtfMultiplier = 1.5;
      } else if (measuredRTF < 0.5) {
        rtfMultiplier = 1.25;
      } else if (measuredRTF > 1.0) {
        // Synthesis is slower than playback! Be conservative.
        rtfMultiplier = 0.75;
      }
    }

    // Charging adjustment: can be more aggressive when plugged in
    double chargingMultiplier = isCharging ? 1.25 : 1.0;

    // Memory pressure adjustment
    double memoryMultiplier = switch (memoryPressure) {
      MemoryPressure.none => 1.0,
      MemoryPressure.moderate => 0.75,
      MemoryPressure.critical => 0.5,
    };

    // Calculate final count
    var segments =
        (baseSegments * rtfMultiplier * chargingMultiplier * memoryMultiplier)
            .round();

    // Never exceed remaining segments
    segments = min(segments, remainingSegments);

    // Minimum of 1 (always synthesize next segment)
    return max(1, segments);
  }

  /// Calculate the target buffer time in milliseconds.
  ///
  /// Adapts the buffer target based on RTF and memory pressure.
  int calculateBufferTargetMs({
    required SynthesisMode synthesisMode,
    required double measuredRTF,
    required MemoryPressure memoryPressure,
  }) {
    // Base target from synthesis mode
    int baseTargetMs = synthesisMode.bufferTargetMs;

    // Aggressive mode: larger buffer
    if (_prefetchMode == PrefetchMode.aggressive) {
      baseTargetMs = (baseTargetMs * 1.5).round();
    } else if (_prefetchMode == PrefetchMode.conservative) {
      baseTargetMs = (baseTargetMs * 0.5).round();
    } else if (_prefetchMode == PrefetchMode.off) {
      return 0;
    }

    // Reduce buffer target if RTF is slow (synthesis can't keep up)
    if (measuredRTF > 0.8) {
      baseTargetMs = (baseTargetMs * 0.75).round();
    }

    // Reduce buffer target under memory pressure
    if (memoryPressure == MemoryPressure.moderate) {
      baseTargetMs = (baseTargetMs * 0.75).round();
    } else if (memoryPressure == MemoryPressure.critical) {
      baseTargetMs = (baseTargetMs * 0.5).round();
    }

    // Ensure minimum viable buffer (10 seconds)
    return max(baseTargetMs, 10000);
  }

  /// Estimate time to synthesize N segments based on RTF.
  ///
  /// Used for progress indicators and timeout calculations.
  Duration estimateSynthesisTime({
    required int segmentCount,
    required double avgSegmentDurationSec,
    required double measuredRTF,
  }) {
    if (measuredRTF <= 0) {
      // Default estimate if no RTF data
      return Duration(seconds: segmentCount * 5);
    }

    final totalAudioSec = segmentCount * avgSegmentDurationSec;
    final synthesisTimeSec = totalAudioSec * measuredRTF;
    return Duration(milliseconds: (synthesisTimeSec * 1000).round());
  }

  /// Log the calculated prefetch parameters for debugging.
  void logPrefetchDecision({
    required int calculatedWindow,
    required int queueLength,
    required int currentPosition,
    required double measuredRTF,
    required SynthesisMode synthesisMode,
    required bool isCharging,
    required MemoryPressure memoryPressure,
  }) {
    PlaybackLog.debug(
      'AdaptivePrefetch: window=$calculatedWindow '
      '(queue=$queueLength, pos=$currentPosition, '
      'rtf=${measuredRTF.toStringAsFixed(2)}, '
      'mode=${synthesisMode.name}, '
      'charging=$isCharging, '
      'memory=${memoryPressure.name})',
    );
  }
}

/// Prefetch mode from user configuration.
///
/// This is defined separately from the runtime config to avoid
/// circular dependencies with the config package.
enum PrefetchMode {
  /// Adapts based on queue length, RTF, and device state.
  /// Recommended for most users.
  adaptive,

  /// Always prefetch maximum allowed tracks.
  /// Uses more battery but ensures smoother playback.
  aggressive,

  /// Prefetch minimally to conserve resources.
  /// Useful on low-end devices or for battery saving.
  conservative,

  /// Disable prefetch entirely (current-track only).
  /// May cause gaps between segments on slower devices.
  off,
}
