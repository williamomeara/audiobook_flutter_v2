import 'dart:convert';

/// Device performance tier based on measured synthesis RTF.
enum DevicePerformanceTier {
  /// RTF < 0.3 - Very fast synthesis, can handle aggressive prefetch.
  flagship,

  /// RTF 0.3-0.5 - Good synthesis speed, balanced approach.
  midRange,

  /// RTF 0.5-0.8 - Acceptable synthesis, conservative prefetch.
  budget,

  /// RTF > 0.8 - Slow synthesis, minimal prefetch.
  legacy,
}

/// Engine-specific configuration based on device performance profile.
class DeviceEngineConfig {
  const DeviceEngineConfig({
    required this.engineId,
    required this.deviceTier,
    required this.prefetchWindowSize,
    required this.prefetchConcurrency,
    required this.preSynthesizeCount,
    required this.enableFullChapterPrefetch,
    required this.fullChapterBatteryThreshold,
    required this.enableNextChapterPrediction,
    required this.cacheRetentionDays,
    required this.maxCacheSizeMB,
    required this.measuredRTF,
    this.tunedAt,
  });

  /// Engine identifier (e.g., "piper:en_GB-alan-medium")
  final String engineId;

  /// Device performance tier.
  final DevicePerformanceTier deviceTier;

  /// How many segments ahead to prefetch.
  final int prefetchWindowSize;

  /// How many parallel synthesis tasks (1 = sequential).
  final int prefetchConcurrency;

  /// How many segments to pre-synthesize on chapter load.
  final int preSynthesizeCount;

  /// Whether to enable full chapter prefetch when conditions allow.
  final bool enableFullChapterPrefetch;

  /// Battery percentage threshold for full chapter prefetch.
  final int fullChapterBatteryThreshold;

  /// Whether to predict and pre-synthesize next chapter.
  final bool enableNextChapterPrediction;

  /// How many days to retain cache entries.
  final int cacheRetentionDays;

  /// Maximum cache size in megabytes.
  final int maxCacheSizeMB;

  /// Measured Real-Time Factor during profiling.
  final double measuredRTF;

  /// When this config was created/tuned.
  final DateTime? tunedAt;

  /// Create config from JSON.
  factory DeviceEngineConfig.fromJson(Map<String, dynamic> json) {
    return DeviceEngineConfig(
      engineId: json['engineId'] as String,
      deviceTier: DevicePerformanceTier.values.firstWhere(
        (e) => e.name == json['deviceTier'],
        orElse: () => DevicePerformanceTier.midRange,
      ),
      prefetchWindowSize: json['prefetchWindowSize'] as int,
      prefetchConcurrency: json['prefetchConcurrency'] as int,
      preSynthesizeCount: json['preSynthesizeCount'] as int,
      enableFullChapterPrefetch: json['enableFullChapterPrefetch'] as bool,
      fullChapterBatteryThreshold: json['fullChapterBatteryThreshold'] as int,
      enableNextChapterPrediction: json['enableNextChapterPrediction'] as bool,
      cacheRetentionDays: json['cacheRetentionDays'] as int,
      maxCacheSizeMB: json['maxCacheSizeMB'] as int,
      measuredRTF: (json['measuredRTF'] as num).toDouble(),
      tunedAt: json['tunedAt'] != null
          ? DateTime.parse(json['tunedAt'] as String)
          : null,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'engineId': engineId,
      'deviceTier': deviceTier.name,
      'prefetchWindowSize': prefetchWindowSize,
      'prefetchConcurrency': prefetchConcurrency,
      'preSynthesizeCount': preSynthesizeCount,
      'enableFullChapterPrefetch': enableFullChapterPrefetch,
      'fullChapterBatteryThreshold': fullChapterBatteryThreshold,
      'enableNextChapterPrediction': enableNextChapterPrediction,
      'cacheRetentionDays': cacheRetentionDays,
      'maxCacheSizeMB': maxCacheSizeMB,
      'measuredRTF': measuredRTF,
      'tunedAt': tunedAt?.toIso8601String(),
    };
  }

  /// Serialize to JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Create flagship (high-performance) config.
  factory DeviceEngineConfig.flagship(String engineId, double rtf) {
    return DeviceEngineConfig(
      engineId: engineId,
      deviceTier: DevicePerformanceTier.flagship,
      prefetchWindowSize: 20,
      prefetchConcurrency: 2,
      preSynthesizeCount: 2,
      enableFullChapterPrefetch: true,
      fullChapterBatteryThreshold: 30,
      enableNextChapterPrediction: true,
      cacheRetentionDays: 14,
      maxCacheSizeMB: 1000,
      measuredRTF: rtf,
      tunedAt: DateTime.now(),
    );
  }

  /// Create mid-range (balanced) config.
  factory DeviceEngineConfig.midRange(String engineId, double rtf) {
    return DeviceEngineConfig(
      engineId: engineId,
      deviceTier: DevicePerformanceTier.midRange,
      prefetchWindowSize: 10,
      prefetchConcurrency: 1,
      preSynthesizeCount: 1,
      enableFullChapterPrefetch: true,
      fullChapterBatteryThreshold: 50,
      enableNextChapterPrediction: false,
      cacheRetentionDays: 7,
      maxCacheSizeMB: 500,
      measuredRTF: rtf,
      tunedAt: DateTime.now(),
    );
  }

  /// Create budget (conservative) config.
  factory DeviceEngineConfig.budget(String engineId, double rtf) {
    return DeviceEngineConfig(
      engineId: engineId,
      deviceTier: DevicePerformanceTier.budget,
      prefetchWindowSize: 5,
      prefetchConcurrency: 1,
      preSynthesizeCount: 1,
      enableFullChapterPrefetch: false,
      fullChapterBatteryThreshold: 80,
      enableNextChapterPrediction: false,
      cacheRetentionDays: 3,
      maxCacheSizeMB: 200,
      measuredRTF: rtf,
      tunedAt: DateTime.now(),
    );
  }

  /// Create legacy (minimal) config.
  factory DeviceEngineConfig.legacy(String engineId, double rtf) {
    return DeviceEngineConfig(
      engineId: engineId,
      deviceTier: DevicePerformanceTier.legacy,
      prefetchWindowSize: 3,
      prefetchConcurrency: 1,
      preSynthesizeCount: 1,
      enableFullChapterPrefetch: false,
      fullChapterBatteryThreshold: 100, // Only when charging
      enableNextChapterPrediction: false,
      cacheRetentionDays: 1,
      maxCacheSizeMB: 100,
      measuredRTF: rtf,
      tunedAt: DateTime.now(),
    );
  }

  /// Create default config when no profiling has been done.
  factory DeviceEngineConfig.defaultConfig(String engineId) {
    return DeviceEngineConfig(
      engineId: engineId,
      deviceTier: DevicePerformanceTier.midRange, // Assume mid-range until profiled
      prefetchWindowSize: 10,
      prefetchConcurrency: 1,
      preSynthesizeCount: 1,
      enableFullChapterPrefetch: false,
      fullChapterBatteryThreshold: 50,
      enableNextChapterPrediction: false,
      cacheRetentionDays: 7,
      maxCacheSizeMB: 500,
      measuredRTF: 0.5, // Assumed default
      tunedAt: null, // Not yet tuned
    );
  }

  @override
  String toString() {
    return 'DeviceEngineConfig($engineId: $deviceTier, RTF: ${measuredRTF.toStringAsFixed(2)}, '
        'prefetch: $prefetchWindowSize segs, concurrency: $prefetchConcurrency)';
  }
}

/// Device synthesis profile from benchmarking.
class DeviceProfile {
  const DeviceProfile({
    required this.engineId,
    required this.avgSynthesisMs,
    required this.avgAudioDurationMs,
    required this.rtf,
    required this.segmentCount,
    required this.profiledAt,
  });

  /// Engine that was profiled.
  final String engineId;

  /// Average synthesis time in milliseconds.
  final int avgSynthesisMs;

  /// Average audio duration in milliseconds.
  final int avgAudioDurationMs;

  /// Real-Time Factor = synthesis time / audio duration.
  final double rtf;

  /// Number of segments used for profiling.
  final int segmentCount;

  /// When profiling was performed.
  final DateTime profiledAt;

  /// Classify device tier based on RTF.
  DevicePerformanceTier get tier {
    if (rtf < 0.3) return DevicePerformanceTier.flagship;
    if (rtf < 0.5) return DevicePerformanceTier.midRange;
    if (rtf < 0.8) return DevicePerformanceTier.budget;
    return DevicePerformanceTier.legacy;
  }

  @override
  String toString() {
    return 'DeviceProfile($engineId: RTF ${rtf.toStringAsFixed(2)}, tier: $tier, '
        'avg synthesis: ${avgSynthesisMs}ms)';
  }
}
