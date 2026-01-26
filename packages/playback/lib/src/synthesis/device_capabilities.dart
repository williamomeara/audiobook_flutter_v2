import 'dart:io';
import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

/// Detected device capabilities for tuning synthesis concurrency.
///
/// This class provides a pragmatic assessment of device capabilities
/// without requiring platform-specific native plugins. It uses:
///
/// - `Platform.numberOfProcessors` for total CPU cores
/// - Heuristics for estimating performance vs efficiency cores
/// - Battery status for power-constrained mode detection
///
/// ## Limitations
///
/// - Cannot detect actual performance cores vs efficiency cores
/// - No direct thermal state access (would require native plugin)
/// - Battery temperature not available on all devices
///
/// ## Best Practices Applied
///
/// - Use device_info_plus for architecture if needed
/// - Test on real physical devices, not emulators
/// - Profile in release mode for accurate performance
class DeviceCapabilities {
  /// Total number of CPU cores.
  final int totalCores;

  /// Estimated number of performance cores.
  /// Typically half of total on modern big.LITTLE chips.
  final int estimatedPerformanceCores;

  /// Estimated number of efficiency cores.
  final int estimatedEfficiencyCores;

  /// Whether the device appears to be charging.
  final bool isCharging;

  /// Battery percentage (0-100) if available.
  final int? batteryLevel;

  /// Whether battery saver mode appears active.
  final bool batteryOptimized;

  /// Platform (android/ios/linux/etc).
  final String platform;

  /// Timestamp when capabilities were detected.
  final DateTime detectedAt;

  const DeviceCapabilities({
    required this.totalCores,
    required this.estimatedPerformanceCores,
    required this.estimatedEfficiencyCores,
    required this.isCharging,
    this.batteryLevel,
    required this.batteryOptimized,
    required this.platform,
    required this.detectedAt,
  });

  /// Detect current device capabilities.
  ///
  /// This is an async operation due to battery status queries.
  /// Results are cached - call again to refresh.
  static Future<DeviceCapabilities> detect() async {
    final totalCores = Platform.numberOfProcessors;

    // Estimate performance cores based on common architectures:
    // - 4 cores: Likely all same (older devices), assume 2 perf
    // - 6 cores: Typically 2 perf + 4 eff (mid-range)
    // - 8 cores: Typically 4 perf + 4 eff (flagship)
    // - 8+ cores: Assume half are performance
    final estimatedPerf = _estimatePerformanceCores(totalCores);

    // Check battery status
    final battery = Battery();
    int? batteryLevel;
    bool isCharging = false;
    bool batteryOptimized = false;

    try {
      batteryLevel = await battery.batteryLevel;
      final state = await battery.batteryState;
      isCharging = state == BatteryState.charging ||
          state == BatteryState.full;

      // Check battery saver mode (if available)
      if (Platform.isAndroid) {
        final saveMode = await battery.isInBatterySaveMode;
        batteryOptimized = saveMode;
      }

      // Low battery without charging suggests power constraints
      if (!isCharging && batteryLevel < 20) {
        batteryOptimized = true;
      }
    } catch (_) {
      // Battery info not available (emulator, desktop, etc.)
    }

    return DeviceCapabilities(
      totalCores: totalCores,
      estimatedPerformanceCores: estimatedPerf,
      estimatedEfficiencyCores: totalCores - estimatedPerf,
      isCharging: isCharging,
      batteryLevel: batteryLevel,
      batteryOptimized: batteryOptimized,
      platform: Platform.operatingSystem,
      detectedAt: DateTime.now(),
    );
  }

  /// Recommended maximum concurrency for this device.
  ///
  /// Based on:
  /// - Performance cores (use those, leave efficiency for OS/UI)
  /// - Leave 1 core for UI thread
  /// - Cap at 4 (diminishing returns beyond)
  /// - Reduce if battery optimized
  int get recommendedMaxConcurrency {
    // Base: performance cores - 1 (leave one for UI)
    int maxConcurrency = (estimatedPerformanceCores - 1).clamp(1, 4);

    // If battery optimized, be more conservative
    if (batteryOptimized) {
      maxConcurrency = (maxConcurrency * 0.75).ceil().clamp(1, 4);
    }

    return maxConcurrency;
  }

  /// Suggested baseline concurrency (starting point for learning).
  ///
  /// More conservative than max - lets the system learn upward.
  int get suggestedBaselineConcurrency {
    // Start at half of max, minimum 1
    return (recommendedMaxConcurrency / 2).ceil().clamp(1, 2);
  }

  /// Device tier estimate for UI display.
  DeviceTier get estimatedTier {
    if (totalCores >= 8 && estimatedPerformanceCores >= 4) {
      return DeviceTier.highEnd;
    } else if (totalCores >= 6) {
      return DeviceTier.midRange;
    }
    return DeviceTier.lowEnd;
  }

  /// Whether this device can likely achieve real-time synthesis.
  ///
  /// Conservative estimate based on hardware. Actual performance
  /// will be learned through synthesis.
  bool get likelyCapableOfRealtime {
    // Assume 4+ cores and mid-range or better can do realtime
    return totalCores >= 4 && estimatedTier != DeviceTier.lowEnd;
  }

  static int _estimatePerformanceCores(int totalCores) {
    // Heuristics for common ARM big.LITTLE configurations
    return switch (totalCores) {
      <= 2 => 1, // Very old or efficiency-focused
      <= 4 => 2, // Older devices, assume half perf
      <= 6 => 2, // Typical: 2 big + 4 little
      <= 8 => 4, // Typical: 4 big + 4 little
      _ => (totalCores / 2).ceil(), // Large core counts: assume half
    };
  }

  @override
  String toString() => 'DeviceCapabilities('
      'cores: $totalCores ($estimatedPerformanceCores perf + $estimatedEfficiencyCores eff), '
      'maxConcurrency: $recommendedMaxConcurrency, '
      'tier: ${estimatedTier.name}, '
      'battery: ${batteryLevel ?? "?"}%, '
      'charging: $isCharging, '
      'optimized: $batteryOptimized)';

  Map<String, dynamic> toJson() => {
        'totalCores': totalCores,
        'estimatedPerformanceCores': estimatedPerformanceCores,
        'estimatedEfficiencyCores': estimatedEfficiencyCores,
        'recommendedMaxConcurrency': recommendedMaxConcurrency,
        'suggestedBaselineConcurrency': suggestedBaselineConcurrency,
        'estimatedTier': estimatedTier.name,
        'isCharging': isCharging,
        'batteryLevel': batteryLevel,
        'batteryOptimized': batteryOptimized,
        'platform': platform,
        'likelyCapableOfRealtime': likelyCapableOfRealtime,
        'detectedAt': detectedAt.toIso8601String(),
      };
}

/// Estimated device performance tier.
enum DeviceTier {
  /// Low-end device (4 or fewer cores, likely older).
  /// May struggle with real-time synthesis.
  lowEnd,

  /// Mid-range device (6 cores, typical modern phone).
  /// Should handle real-time synthesis.
  midRange,

  /// High-end device (8+ cores, flagship).
  /// Excellent synthesis performance.
  highEnd,
}

/// Extension for DeviceTier display.
extension DeviceTierDisplay on DeviceTier {
  String get displayName => switch (this) {
        DeviceTier.lowEnd => 'Basic',
        DeviceTier.midRange => 'Standard',
        DeviceTier.highEnd => 'Premium',
      };

  String get description => switch (this) {
        DeviceTier.lowEnd => 'May need pre-synthesis for smooth playback',
        DeviceTier.midRange => 'Good performance for most voices',
        DeviceTier.highEnd => 'Excellent performance, all voices supported',
      };
}
