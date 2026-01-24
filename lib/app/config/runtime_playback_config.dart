import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Prefetch mode for controlling synthesis aggressiveness.
///
/// This determines how aggressively the app pre-synthesizes upcoming
/// audio segments. All synthesis is performed locally on-device.
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

/// Runtime-configurable playback settings with persistence.
///
/// This class provides runtime-adjustable playback parameters that
/// persist across app restarts. It complements the compile-time
/// constants in [PlaybackConfig] by allowing user customization.
///
/// All TTS synthesis is performed locally on-device using ONNX Runtime.
/// These settings control local resource usage, not network behavior.
///
/// Example usage:
/// ```dart
/// // Load persisted config (or defaults)
/// final config = await RuntimePlaybackConfig.load();
///
/// // Modify settings
/// final updated = config.copyWith(prefetchMode: PrefetchMode.aggressive);
/// await updated.save();
/// ```
class RuntimePlaybackConfig {
  RuntimePlaybackConfig({
    this.cacheBudgetMB,
    this.cacheMaxAgeDays,
    this.prefetchMode = PrefetchMode.adaptive,
    this.parallelSynthesisThreads,
    this.resumeDelayMs = 500,
    this.rateIndependentSynthesis = true,
    DateTime? lastModified,
  }) : lastModified = lastModified ?? DateTime.now();

  // ═══════════════════════════════════════════════════════════════════
  // Cache Settings
  // ═══════════════════════════════════════════════════════════════════

  /// Maximum cache size in megabytes for synthesized audio.
  ///
  /// Set to null for auto-configuration based on available storage.
  /// The cache stores locally synthesized audio segments.
  ///
  /// Default: null (auto-configure, typically 500 MB - 2 GB based on device)
  final int? cacheBudgetMB;

  /// Maximum age of cached audio in days.
  ///
  /// Cached segments older than this are eligible for automatic deletion.
  /// Set to null to use default (7 days).
  final int? cacheMaxAgeDays;

  // ═══════════════════════════════════════════════════════════════════
  // Prefetch Settings
  // ═══════════════════════════════════════════════════════════════════

  /// How aggressively to prefetch upcoming audio segments.
  ///
  /// See [PrefetchMode] for available options.
  /// Default: [PrefetchMode.adaptive]
  final PrefetchMode prefetchMode;

  /// Number of parallel synthesis threads.
  ///
  /// Set to null for auto-detection based on device capabilities.
  /// Higher values use more memory but may synthesize faster.
  ///
  /// Clamped to 1-4 when set explicitly.
  final int? parallelSynthesisThreads;

  /// Delay in milliseconds before resuming prefetch after user interaction.
  ///
  /// After seeking or navigation, prefetch pauses briefly to avoid
  /// wasting resources on segments the user may skip past.
  ///
  /// Default: 500ms
  final int resumeDelayMs;

  // ═══════════════════════════════════════════════════════════════════
  // Synthesis Settings
  // ═══════════════════════════════════════════════════════════════════

  /// Whether to use rate-independent synthesis.
  ///
  /// When true (default), audio is always synthesized at 1.0x speed
  /// and playback rate is adjusted by the audio player. This maximizes
  /// cache hits when users change playback speed.
  ///
  /// When false, the requested playback rate is baked into synthesis,
  /// which invalidates cache entries when rate changes.
  final bool rateIndependentSynthesis;

  // ═══════════════════════════════════════════════════════════════════
  // Metadata
  // ═══════════════════════════════════════════════════════════════════

  /// When this configuration was last modified.
  final DateTime lastModified;

  // ═══════════════════════════════════════════════════════════════════
  // Persistence
  // ═══════════════════════════════════════════════════════════════════

  static const String _prefsKey = 'runtime_playback_config_v1';

  /// Load configuration from SharedPreferences.
  ///
  /// Returns default configuration if no saved config exists or
  /// if there's an error loading the config.
  static Future<RuntimePlaybackConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);

      if (json == null) {
        developer.log(
          'RuntimePlaybackConfig: No saved config, using defaults',
          name: 'RuntimePlaybackConfig',
        );
        return RuntimePlaybackConfig();
      }

      final config = RuntimePlaybackConfig.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      developer.log(
        'RuntimePlaybackConfig: Loaded from storage',
        name: 'RuntimePlaybackConfig',
      );
      return config;
    } catch (e, stackTrace) {
      developer.log(
        'RuntimePlaybackConfig: Error loading: $e',
        name: 'RuntimePlaybackConfig',
        error: e,
        stackTrace: stackTrace,
      );
      return RuntimePlaybackConfig();
    }
  }

  /// Persist this configuration to SharedPreferences.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(toJson()));
      developer.log(
        'RuntimePlaybackConfig: Saved to storage',
        name: 'RuntimePlaybackConfig',
      );
    } catch (e, stackTrace) {
      developer.log(
        'RuntimePlaybackConfig: Error saving: $e',
        name: 'RuntimePlaybackConfig',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Create a modified copy with automatic change logging.
  RuntimePlaybackConfig copyWith({
    int? cacheBudgetMB,
    int? cacheMaxAgeDays,
    PrefetchMode? prefetchMode,
    int? parallelSynthesisThreads,
    int? resumeDelayMs,
    bool? rateIndependentSynthesis,
  }) {
    // Log significant changes
    _logChanges(
      cacheBudgetMB: cacheBudgetMB,
      prefetchMode: prefetchMode,
      parallelSynthesisThreads: parallelSynthesisThreads,
    );

    // Clamp parallelSynthesisThreads if provided
    final clampedThreads = parallelSynthesisThreads != null
        ? parallelSynthesisThreads.clamp(1, 4)
        : this.parallelSynthesisThreads;

    return RuntimePlaybackConfig(
      cacheBudgetMB: cacheBudgetMB ?? this.cacheBudgetMB,
      cacheMaxAgeDays: cacheMaxAgeDays ?? this.cacheMaxAgeDays,
      prefetchMode: prefetchMode ?? this.prefetchMode,
      parallelSynthesisThreads: clampedThreads,
      resumeDelayMs: resumeDelayMs ?? this.resumeDelayMs,
      rateIndependentSynthesis:
          rateIndependentSynthesis ?? this.rateIndependentSynthesis,
      lastModified: DateTime.now(),
    );
  }

  void _logChanges({
    int? cacheBudgetMB,
    PrefetchMode? prefetchMode,
    int? parallelSynthesisThreads,
  }) {
    if (cacheBudgetMB != null && cacheBudgetMB != this.cacheBudgetMB) {
      developer.log(
        'Config change: cacheBudgetMB ${this.cacheBudgetMB} -> $cacheBudgetMB',
        name: 'RuntimePlaybackConfig',
      );
    }
    if (prefetchMode != null && prefetchMode != this.prefetchMode) {
      developer.log(
        'Config change: prefetchMode ${this.prefetchMode.name} -> ${prefetchMode.name}',
        name: 'RuntimePlaybackConfig',
      );
    }
    if (parallelSynthesisThreads != null &&
        parallelSynthesisThreads != this.parallelSynthesisThreads) {
      developer.log(
        'Config change: parallelSynthesisThreads '
        '${this.parallelSynthesisThreads} -> $parallelSynthesisThreads',
        name: 'RuntimePlaybackConfig',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Serialization
  // ═══════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
        'cacheBudgetMB': cacheBudgetMB,
        'cacheMaxAgeDays': cacheMaxAgeDays,
        'prefetchMode': prefetchMode.name,
        'parallelSynthesisThreads': parallelSynthesisThreads,
        'resumeDelayMs': resumeDelayMs,
        'rateIndependentSynthesis': rateIndependentSynthesis,
        'lastModified': lastModified.toIso8601String(),
      };

  factory RuntimePlaybackConfig.fromJson(Map<String, dynamic> json) {
    return RuntimePlaybackConfig(
      cacheBudgetMB: json['cacheBudgetMB'] as int?,
      cacheMaxAgeDays: json['cacheMaxAgeDays'] as int?,
      prefetchMode: _parsePrefetchMode(json['prefetchMode']),
      parallelSynthesisThreads: json['parallelSynthesisThreads'] as int?,
      resumeDelayMs: json['resumeDelayMs'] as int? ?? 500,
      rateIndependentSynthesis:
          json['rateIndependentSynthesis'] as bool? ?? true,
      lastModified: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'] as String)
          : null,
    );
  }

  static PrefetchMode _parsePrefetchMode(dynamic value) {
    if (value == null) return PrefetchMode.adaptive;
    if (value is String) {
      return PrefetchMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => PrefetchMode.adaptive,
      );
    }
    return PrefetchMode.adaptive;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Convenience Methods
  // ═══════════════════════════════════════════════════════════════════

  /// Get the effective cache budget in bytes.
  ///
  /// Returns the configured value, or a default based on device storage.
  int get effectiveCacheBudgetBytes {
    if (cacheBudgetMB != null) {
      return cacheBudgetMB! * 1024 * 1024;
    }
    // Default: 500 MB (will be overridden by auto-configure if available)
    return 500 * 1024 * 1024;
  }

  /// Get the effective max age in milliseconds.
  int get effectiveMaxAgeMs {
    final days = cacheMaxAgeDays ?? 7;
    return days * 24 * 60 * 60 * 1000;
  }

  /// Get the effective resume delay as a Duration.
  Duration get effectiveResumeDelay => Duration(milliseconds: resumeDelayMs);

  /// Whether prefetch is enabled.
  bool get isPrefetchEnabled => prefetchMode != PrefetchMode.off;

  @override
  String toString() {
    return 'RuntimePlaybackConfig('
        'cacheBudgetMB: $cacheBudgetMB, '
        'cacheMaxAgeDays: $cacheMaxAgeDays, '
        'prefetchMode: ${prefetchMode.name}, '
        'parallelSynthesisThreads: $parallelSynthesisThreads, '
        'resumeDelayMs: $resumeDelayMs, '
        'rateIndependentSynthesis: $rateIndependentSynthesis)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RuntimePlaybackConfig &&
        other.cacheBudgetMB == cacheBudgetMB &&
        other.cacheMaxAgeDays == cacheMaxAgeDays &&
        other.prefetchMode == prefetchMode &&
        other.parallelSynthesisThreads == parallelSynthesisThreads &&
        other.resumeDelayMs == resumeDelayMs &&
        other.rateIndependentSynthesis == rateIndependentSynthesis;
  }

  @override
  int get hashCode => Object.hash(
        cacheBudgetMB,
        cacheMaxAgeDays,
        prefetchMode,
        parallelSynthesisThreads,
        resumeDelayMs,
        rateIndependentSynthesis,
      );
}
