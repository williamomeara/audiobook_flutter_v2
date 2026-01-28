import 'dart:developer' as developer;

import '../database/app_database.dart';
import '../database/daos/settings_dao.dart';

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
    this.resumeDelayMs = 500,
    this.rateIndependentSynthesis = true,
    this.synthesisStrategyState,
    this.engineCalibration,
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

  /// Persisted state for the synthesis strategy (e.g., learned RTF values).
  ///
  /// This is an opaque JSON map that the playback package's SynthesisStrategy
  /// uses to persist learned parameters across app restarts.
  ///
  /// For AdaptiveSynthesisStrategy, this includes:
  /// - Average RTF (real-time factor)
  /// - Number of completed synthesis operations
  /// - Adjusted preSynthesizeCount
  final Map<String, dynamic>? synthesisStrategyState;

  // ═══════════════════════════════════════════════════════════════════
  // Engine Calibration Settings (Phase 2)
  // ═══════════════════════════════════════════════════════════════════

  /// Calibration results for each TTS engine.
  ///
  /// Maps engine type (e.g., 'kokoro', 'piper') to calibration data.
  /// Each entry contains:
  /// - 'optimalConcurrency': int - optimal parallel concurrency for this device
  /// - 'speedup': double - measured speedup factor vs sequential
  /// - 'rtf': double - real-time factor at optimal concurrency
  /// - 'calibratedAt': ISO8601 string - when calibration was performed
  ///
  /// Example:
  /// ```json
  /// {
  ///   "kokoro": {
  ///     "optimalConcurrency": 3,
  ///     "speedup": 1.65,
  ///     "rtf": 2.1,
  ///     "calibratedAt": "2026-01-24T10:30:00Z"
  ///   }
  /// }
  /// ```
  final Map<String, Map<String, dynamic>>? engineCalibration;

  // ═══════════════════════════════════════════════════════════════════
  // Metadata
  // ═══════════════════════════════════════════════════════════════════

  /// When this configuration was last modified.
  final DateTime lastModified;

  // ═══════════════════════════════════════════════════════════════════
  // Persistence
  // ═══════════════════════════════════════════════════════════════════

  /// Load configuration from SQLite.
  ///
  /// Returns default configuration if no saved config exists or
  /// if there's an error loading the config.
  static Future<RuntimePlaybackConfig> load() async {
    try {
      final db = await AppDatabase.instance;
      final settingsDao = SettingsDao(db);
      final configMap = await settingsDao.getSetting<Map<String, dynamic>>(
        SettingsKeys.runtimePlaybackConfig,
      );

      if (configMap == null) {
        developer.log(
          'RuntimePlaybackConfig: No saved config, using defaults',
          name: 'RuntimePlaybackConfig',
        );
        return RuntimePlaybackConfig();
      }

      final config = RuntimePlaybackConfig.fromJson(configMap);
      developer.log(
        'RuntimePlaybackConfig: Loaded from SQLite',
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

  /// Persist this configuration to SQLite.
  Future<void> save() async {
    try {
      final db = await AppDatabase.instance;
      final settingsDao = SettingsDao(db);
      await settingsDao.setSetting(
        SettingsKeys.runtimePlaybackConfig,
        toJson(),
      );
      developer.log(
        'RuntimePlaybackConfig: Saved to SQLite',
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
    int? resumeDelayMs,
    bool? rateIndependentSynthesis,
    Map<String, dynamic>? synthesisStrategyState,
    Map<String, Map<String, dynamic>>? engineCalibration,
  }) {
    // Log significant changes
    _logChanges(
      cacheBudgetMB: cacheBudgetMB,
      prefetchMode: prefetchMode,
    );

    return RuntimePlaybackConfig(
      cacheBudgetMB: cacheBudgetMB ?? this.cacheBudgetMB,
      cacheMaxAgeDays: cacheMaxAgeDays ?? this.cacheMaxAgeDays,
      prefetchMode: prefetchMode ?? this.prefetchMode,
      resumeDelayMs: resumeDelayMs ?? this.resumeDelayMs,
      rateIndependentSynthesis:
          rateIndependentSynthesis ?? this.rateIndependentSynthesis,
      synthesisStrategyState:
          synthesisStrategyState ?? this.synthesisStrategyState,
      engineCalibration: engineCalibration ?? this.engineCalibration,
      lastModified: DateTime.now(),
    );
  }

  void _logChanges({
    int? cacheBudgetMB,
    PrefetchMode? prefetchMode,
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
  }

  // ═══════════════════════════════════════════════════════════════════
  // Serialization
  // ═══════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
        'cacheBudgetMB': cacheBudgetMB,
        'cacheMaxAgeDays': cacheMaxAgeDays,
        'prefetchMode': prefetchMode.name,
        'resumeDelayMs': resumeDelayMs,
        'rateIndependentSynthesis': rateIndependentSynthesis,
        'synthesisStrategyState': synthesisStrategyState,
        'engineCalibration': engineCalibration,
        'lastModified': lastModified.toIso8601String(),
      };

  factory RuntimePlaybackConfig.fromJson(Map<String, dynamic> json) {
    return RuntimePlaybackConfig(
      cacheBudgetMB: json['cacheBudgetMB'] as int?,
      cacheMaxAgeDays: json['cacheMaxAgeDays'] as int?,
      prefetchMode: _parsePrefetchMode(json['prefetchMode']),
      resumeDelayMs: json['resumeDelayMs'] as int? ?? 500,
      rateIndependentSynthesis:
          json['rateIndependentSynthesis'] as bool? ?? true,
      synthesisStrategyState:
          json['synthesisStrategyState'] as Map<String, dynamic>?,
      engineCalibration: _parseEngineCalibration(json['engineCalibration']),
      lastModified: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'] as String)
          : null,
    );
  }

  static Map<String, Map<String, dynamic>>? _parseEngineCalibration(
    dynamic value,
  ) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) return null;

    final result = <String, Map<String, dynamic>>{};
    for (final entry in value.entries) {
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = entry.value as Map<String, dynamic>;
      }
    }
    return result.isEmpty ? null : result;
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

  // ═══════════════════════════════════════════════════════════════════
  // Engine Calibration Methods
  // ═══════════════════════════════════════════════════════════════════

  /// Check if an engine has been calibrated.
  bool isEngineCalibrated(String engineType) {
    return engineCalibration?.containsKey(engineType.toLowerCase()) ?? false;
  }

  /// Get the optimal concurrency for an engine (from calibration or default).
  ///
  /// Returns calibrated value if available, otherwise falls back to
  /// PlaybackConfig defaults.
  int getOptimalConcurrency(String engineType) {
    final key = engineType.toLowerCase();
    if (engineCalibration != null && engineCalibration!.containsKey(key)) {
      final data = engineCalibration![key]!;
      return data['optimalConcurrency'] as int? ?? _defaultConcurrency(key);
    }
    return _defaultConcurrency(key);
  }

  /// Get calibration speedup for an engine (null if not calibrated).
  double? getCalibrationSpeedup(String engineType) {
    final key = engineType.toLowerCase();
    if (engineCalibration != null && engineCalibration!.containsKey(key)) {
      return engineCalibration![key]!['speedup'] as double?;
    }
    return null;
  }

  /// Get calibration RTF for an engine (null if not calibrated).
  double? getCalibrationRtf(String engineType) {
    final key = engineType.toLowerCase();
    if (engineCalibration != null && engineCalibration!.containsKey(key)) {
      return engineCalibration![key]!['rtf'] as double?;
    }
    return null;
  }

  /// Get when an engine was calibrated (null if not calibrated).
  DateTime? getCalibrationTime(String engineType) {
    final key = engineType.toLowerCase();
    if (engineCalibration != null && engineCalibration!.containsKey(key)) {
      final timestamp = engineCalibration![key]!['calibratedAt'] as String?;
      if (timestamp != null) {
        return DateTime.tryParse(timestamp);
      }
    }
    return null;
  }

  /// Update calibration for a specific engine.
  ///
  /// Returns a new config with the calibration added/updated.
  RuntimePlaybackConfig withEngineCalibration({
    required String engineType,
    required int optimalConcurrency,
    required double speedup,
    required double rtf,
  }) {
    final key = engineType.toLowerCase();
    final existing = engineCalibration ?? {};
    final updated = Map<String, Map<String, dynamic>>.from(existing);
    updated[key] = {
      'optimalConcurrency': optimalConcurrency,
      'speedup': speedup,
      'rtf': rtf,
      'calibratedAt': DateTime.now().toIso8601String(),
    };
    return copyWith(engineCalibration: updated);
  }

  static int _defaultConcurrency(String engineType) {
    return switch (engineType) {
      'kokoro' => 2,
      'piper' => 2,
      'supertonic' => 2,
      _ => 1,
    };
  }

  @override
  String toString() {
    return 'RuntimePlaybackConfig('
        'cacheBudgetMB: $cacheBudgetMB, '
        'cacheMaxAgeDays: $cacheMaxAgeDays, '
        'prefetchMode: ${prefetchMode.name}, '
        'resumeDelayMs: $resumeDelayMs, '
        'rateIndependentSynthesis: $rateIndependentSynthesis, '
        'hasStrategyState: ${synthesisStrategyState != null}, '
        'calibratedEngines: ${engineCalibration?.keys.toList()})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RuntimePlaybackConfig &&
        other.cacheBudgetMB == cacheBudgetMB &&
        other.cacheMaxAgeDays == cacheMaxAgeDays &&
        other.prefetchMode == prefetchMode &&
        other.resumeDelayMs == resumeDelayMs &&
        other.rateIndependentSynthesis == rateIndependentSynthesis &&
        _mapEquals(other.synthesisStrategyState, synthesisStrategyState) &&
        _nestedMapEquals(other.engineCalibration, engineCalibration);
  }

  static bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  static bool _nestedMapEquals(
    Map<String, Map<String, dynamic>>? a,
    Map<String, Map<String, dynamic>>? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_mapEquals(a[key], b[key])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        cacheBudgetMB,
        cacheMaxAgeDays,
        prefetchMode,
        resumeDelayMs,
        rateIndependentSynthesis,
        synthesisStrategyState?.hashCode,
        engineCalibration?.hashCode,
      );
}
