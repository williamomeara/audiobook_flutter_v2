# Configuration Flexibility Implementation Plan

## Overview

This document outlines a plan to address the configuration flexibility issues (F1-F5) identified in the architecture audit, along with related edge cases that benefit from a unified configuration system.

**Note:** This app performs all text-to-speech synthesis entirely on-device using local ONNX Runtime inference. There is no server-side processing, cloud APIs, or network dependency for synthesis. Configuration is stored locally using SharedPreferences. This offline-first architecture means:
- Configuration changes take effect immediately without network round-trips
- All auto-tuning and adaptation decisions are made locally based on device metrics
- Users can use the app in airplane mode with full functionality (after initial voice model download)

## Problem Statement

The current playback configuration system has several limitations:
1. Most values are compile-time constants in `PlaybackConfig`
2. No runtime adjustability based on device capabilities
3. Conflicting configuration sources (PlaybackConfig vs DeviceEngineConfig)
4. No user-facing controls for power users

## Goals

1. **Runtime Configuration**: Allow key parameters to be adjusted without code changes
2. **Device Awareness**: Automatically tune based on device capabilities
3. **User Control**: Expose appropriate settings to users who want fine-tuning
4. **Backward Compatibility**: Default behavior unchanged for existing users
5. **Persistence**: Configuration survives app restarts
6. **Observability**: Configuration changes are logged and traceable
7. **Safety**: Auto-tuning includes rollback mechanisms

---

## Architecture: Configuration Persistence System

Before diving into individual issues, we need a foundation for persisting runtime configuration.

### RuntimePlaybackConfig Class

```dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized runtime configuration with persistence.
/// 
/// This is the single source of truth for all configurable playback parameters.
/// Values here override compile-time defaults when set.
class RuntimePlaybackConfig {
  RuntimePlaybackConfig({
    this.cacheBudgetBytes,
    this.cacheMaxAgeDays,
    this.prefetchMode = PrefetchMode.adaptive,
    this.parallelSynthesisThreads,
    this.resumeDelayMs = 500,
    this.rateIndependentSynthesis = true,
    DateTime? lastModified,
  }) : lastModified = lastModified ?? DateTime.now();

  // Cache settings
  final int? cacheBudgetBytes;      // null = auto
  final int? cacheMaxAgeDays;       // null = default (7)
  
  // Prefetch settings
  final PrefetchMode prefetchMode;
  final int? parallelSynthesisThreads; // null = auto-detect
  final int resumeDelayMs;
  
  // Synthesis settings
  final bool rateIndependentSynthesis;
  
  // Metadata
  final DateTime lastModified;
  
  static const String _prefsKey = 'runtime_playback_config_v1';
  
  /// Load from SharedPreferences, returning defaults if not persisted.
  static Future<RuntimePlaybackConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json == null) {
        developer.log('RuntimePlaybackConfig: No saved config, using defaults');
        return RuntimePlaybackConfig();
      }
      final config = RuntimePlaybackConfig.fromJson(jsonDecode(json));
      developer.log('RuntimePlaybackConfig: Loaded from storage');
      return config;
    } catch (e) {
      developer.log('RuntimePlaybackConfig: Error loading: $e');
      return RuntimePlaybackConfig();
    }
  }
  
  /// Persist current configuration.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
    developer.log('RuntimePlaybackConfig: Saved to storage');
  }
  
  /// Create a modified copy with logging.
  RuntimePlaybackConfig copyWith({
    int? cacheBudgetBytes,
    int? cacheMaxAgeDays,
    PrefetchMode? prefetchMode,
    int? parallelSynthesisThreads,
    int? resumeDelayMs,
    bool? rateIndependentSynthesis,
  }) {
    _logChanges(
      cacheBudgetBytes: cacheBudgetBytes,
      prefetchMode: prefetchMode,
      parallelSynthesisThreads: parallelSynthesisThreads,
    );
    
    return RuntimePlaybackConfig(
      cacheBudgetBytes: cacheBudgetBytes ?? this.cacheBudgetBytes,
      cacheMaxAgeDays: cacheMaxAgeDays ?? this.cacheMaxAgeDays,
      prefetchMode: prefetchMode ?? this.prefetchMode,
      parallelSynthesisThreads: parallelSynthesisThreads ?? this.parallelSynthesisThreads,
      resumeDelayMs: resumeDelayMs ?? this.resumeDelayMs,
      rateIndependentSynthesis: rateIndependentSynthesis ?? this.rateIndependentSynthesis,
      lastModified: DateTime.now(),
    );
  }
  
  void _logChanges({
    int? cacheBudgetBytes,
    PrefetchMode? prefetchMode,
    int? parallelSynthesisThreads,
  }) {
    if (cacheBudgetBytes != null && cacheBudgetBytes != this.cacheBudgetBytes) {
      developer.log('Config change: cacheBudgetBytes ${this.cacheBudgetBytes} -> $cacheBudgetBytes');
    }
    if (prefetchMode != null && prefetchMode != this.prefetchMode) {
      developer.log('Config change: prefetchMode ${this.prefetchMode} -> $prefetchMode');
    }
    if (parallelSynthesisThreads != null && parallelSynthesisThreads != this.parallelSynthesisThreads) {
      developer.log('Config change: parallelSynthesisThreads ${this.parallelSynthesisThreads} -> $parallelSynthesisThreads');
    }
  }
  
  Map<String, dynamic> toJson() => {
    'cacheBudgetBytes': cacheBudgetBytes,
    'cacheMaxAgeDays': cacheMaxAgeDays,
    'prefetchMode': prefetchMode.name,
    'parallelSynthesisThreads': parallelSynthesisThreads,
    'resumeDelayMs': resumeDelayMs,
    'rateIndependentSynthesis': rateIndependentSynthesis,
    'lastModified': lastModified.toIso8601String(),
  };
  
  factory RuntimePlaybackConfig.fromJson(Map<String, dynamic> json) {
    return RuntimePlaybackConfig(
      cacheBudgetBytes: json['cacheBudgetBytes'] as int?,
      cacheMaxAgeDays: json['cacheMaxAgeDays'] as int?,
      prefetchMode: PrefetchMode.values.byName(json['prefetchMode'] ?? 'adaptive'),
      parallelSynthesisThreads: json['parallelSynthesisThreads'] as int?,
      resumeDelayMs: json['resumeDelayMs'] as int? ?? 500,
      rateIndependentSynthesis: json['rateIndependentSynthesis'] as bool? ?? true,
      lastModified: json['lastModified'] != null 
          ? DateTime.parse(json['lastModified']) 
          : null,
    );
  }
}

enum PrefetchMode {
  /// Adapts based on queue length, RTF, and device state
  adaptive,
  /// Always prefetch maximum allowed tracks
  aggressive,
  /// Prefetch minimally to conserve resources
  conservative,
  /// Disable prefetch entirely (current-track only)
  off,
}
```

### Riverpod Provider Integration

```dart
// In lib/app/config_providers.dart

/// Provider for runtime playback configuration.
/// 
/// This provider loads persisted config on first access and provides
/// methods to update and save configuration changes.
final runtimeConfigProvider = AsyncNotifierProvider<RuntimeConfigNotifier, RuntimePlaybackConfig>(
  RuntimeConfigNotifier.new,
);

class RuntimeConfigNotifier extends AsyncNotifier<RuntimePlaybackConfig> {
  @override
  Future<RuntimePlaybackConfig> build() async {
    return RuntimePlaybackConfig.load();
  }
  
  /// Update configuration and persist.
  Future<void> update(RuntimePlaybackConfig Function(RuntimePlaybackConfig) updater) async {
    final current = state.valueOrNull ?? RuntimePlaybackConfig();
    final updated = updater(current);
    await updated.save();
    state = AsyncData(updated);
  }
  
  /// Reset to defaults.
  Future<void> reset() async {
    final defaults = RuntimePlaybackConfig();
    await defaults.save();
    state = AsyncData(defaults);
    developer.log('RuntimePlaybackConfig: Reset to defaults');
  }
}
```

---

## Issue Analysis

### F1. Hard-coded Prefetch Window Sizes Not Adaptive

**Current State:**
- `maxPrefetchTracks = 10` (static)
- Battery-based modes exist but are limited to 3 presets

**Problem:**
- Doesn't adapt to queue length (prefetching 15 tracks for a 5-track chapter is wasteful)
- Doesn't consider measured RTF (fast devices could prefetch more)
- No adaptation to device capabilities at runtime

**Root Cause Analysis:**
The original design assumed predictable synthesis times. In reality:
- Kokoro RTF varies 0.2-0.8 depending on device
- Piper can be 10x faster on high-end devices
- Queue lengths vary from 3 segments (short chapter) to 200+ (long audiobook chapter)

Note: Network conditions are not a factor since all TTS synthesis is performed locally on-device using ONNX Runtime inference.

**Proposed Solution:**

```dart
/// Calculates optimal prefetch window based on runtime factors.
/// 
/// This replaces the static maxPrefetchTracks with a dynamic calculation
/// that considers the current playback context.
class AdaptivePrefetchConfig {
  final RuntimePlaybackConfig _config;
  
  AdaptivePrefetchConfig(this._config);
  
  /// Calculate the optimal number of tracks to prefetch.
  /// 
  /// Factors considered:
  /// - Current queue length (don't overshoot)
  /// - Measured RTF (fast synthesis = can prefetch more)
  /// - Synthesis mode (quality vs performance)
  /// - Charging state (can be more aggressive when plugged in)
  /// - Memory pressure (reduce if low memory)
  int calculatePrefetchWindow({
    required int queueLength,
    required int currentPosition,
    required double measuredRTF,
    required SynthesisMode mode,
    required bool isCharging,
    required MemoryPressure memoryPressure,
  }) {
    // Honor user's explicit mode choice
    if (_config.prefetchMode == PrefetchMode.off) return 0;
    if (_config.prefetchMode == PrefetchMode.conservative) {
      return min(2, queueLength - currentPosition);
    }
    
    // Calculate remaining tracks
    final remainingTracks = queueLength - currentPosition;
    if (remainingTracks <= 0) return 0;
    
    // Base prefetch from mode defaults
    int baseTracks = mode.maxPrefetchTracks;
    
    // Aggressive mode: 1.5x base
    if (_config.prefetchMode == PrefetchMode.aggressive) {
      baseTracks = (baseTracks * 1.5).round();
    }
    
    // RTF adjustment: if synthesis is fast, prefetch more
    // RTF < 0.3 means synthesis is 3x faster than playback
    double rtfMultiplier = 1.0;
    if (measuredRTF < 0.3) {
      rtfMultiplier = 1.5;
    } else if (measuredRTF < 0.5) {
      rtfMultiplier = 1.25;
    } else if (measuredRTF > 1.0) {
      // Synthesis is slower than playback! Be conservative.
      rtfMultiplier = 0.75;
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
    var tracks = (baseTracks * rtfMultiplier * chargingMultiplier * memoryMultiplier).round();
    
    // Never exceed remaining tracks
    tracks = min(tracks, remainingTracks);
    
    // Minimum of 1 (always synthesize next track)
    return max(1, tracks);
  }
  
  /// Estimate time to synthesize N tracks based on RTF.
  /// 
  /// Used for progress indicators and timeout calculations.
  Duration estimateSynthesisTime({
    required int trackCount,
    required double avgTrackDurationSec,
    required double measuredRTF,
  }) {
    final totalAudioSec = trackCount * avgTrackDurationSec;
    final synthesisTimeSec = totalAudioSec * measuredRTF;
    return Duration(milliseconds: (synthesisTimeSec * 1000).round());
  }
}

/// Memory pressure levels from platform.
enum MemoryPressure {
  none,
  moderate, 
  critical,
}
```

**Integration Points:**
1. `BufferScheduler` calls `calculatePrefetchWindow()` before each prefetch cycle
2. `SmartSynthesisManager` provides measured RTF
3. Platform channel provides charging state and memory pressure

**Testing Strategy:**
- Unit tests for boundary conditions (empty queue, RTF extremes)
- Widget tests for mode changes
- Integration tests on low-memory emulator profiles

---

### F2. Resume Timer Not Cancellable

**Current State:**
- `prefetchResumeDelay = 500ms` fixed
- No way to resume prefetch manually

**Problem:**
- User seeks, waits 500ms, seeks again → timer resets unnecessarily
- Can't resume immediately when user finishes seeking
- On fast devices, 500ms is unnecessarily long
- On slow devices, 500ms may be too short for UI to settle

**Root Cause Analysis:**
The 500ms delay was chosen arbitrarily. It should adapt to:
- Device responsiveness (fast devices need less delay)
- User seeking pattern (rapid seeks vs single jump)
- Whether audio is actually playing (no need to rush if paused)

**Proposed Solution:**

```dart
/// Manages prefetch suspension with configurable and cancellable timers.
/// 
/// This replaces the fixed 500ms delay with an intelligent system that
/// adapts to user behavior and allows manual override.
class PrefetchResumeController {
  final RuntimePlaybackConfig _config;
  Timer? _resumeTimer;
  bool _isSuspended = false;
  int _seekCount = 0;
  DateTime? _lastSeekTime;
  VoidCallback? _onResume;
  
  PrefetchResumeController(this._config);
  
  /// Whether prefetch is currently suspended.
  bool get isSuspended => _isSuspended;
  
  /// The current effective delay, considering seek patterns.
  Duration get effectiveDelay {
    final baseDelay = Duration(milliseconds: _config.resumeDelayMs);
    
    // If user is seeking rapidly, increase delay to avoid thrashing
    if (_seekCount >= 3 && 
        _lastSeekTime != null &&
        DateTime.now().difference(_lastSeekTime!) < const Duration(seconds: 2)) {
      // Rapid seeking detected - wait longer
      return baseDelay * 2;
    }
    
    return baseDelay;
  }
  
  /// Register callback for when prefetch should resume.
  void setOnResume(VoidCallback callback) {
    _onResume = callback;
  }
  
  /// Suspend prefetch due to seek/navigation.
  /// 
  /// Automatically schedules resume after delay.
  void suspend() {
    _isSuspended = true;
    _resumeTimer?.cancel();
    
    // Track seek patterns
    final now = DateTime.now();
    if (_lastSeekTime != null && 
        now.difference(_lastSeekTime!) < const Duration(seconds: 2)) {
      _seekCount++;
    } else {
      _seekCount = 1;
    }
    _lastSeekTime = now;
    
    developer.log('PrefetchResumeController: Suspended (seek #$_seekCount)');
    
    // Schedule auto-resume
    _resumeTimer = Timer(effectiveDelay, () {
      _resume();
    });
  }
  
  /// Manually resume prefetch immediately.
  /// 
  /// Use when user action indicates they're done seeking:
  /// - Seek bar released (onChangeEnd)
  /// - Play button pressed after seek
  /// - Chapter selection completed
  void resumeImmediately() {
    developer.log('PrefetchResumeController: Manual resume requested');
    _resumeTimer?.cancel();
    _resume();
  }
  
  /// Cancel any pending resume (e.g., when disposing).
  void cancel() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }
  
  void _resume() {
    if (!_isSuspended) return;
    
    _isSuspended = false;
    _seekCount = 0;
    developer.log('PrefetchResumeController: Resumed');
    _onResume?.call();
  }
  
  /// Update configuration at runtime.
  void updateConfig(RuntimePlaybackConfig newConfig) {
    // If delay changed and we have a pending timer, restart it
    if (_resumeTimer != null && _config.resumeDelayMs != newConfig.resumeDelayMs) {
      suspend(); // Will restart timer with new delay
    }
  }
}
```

**Integration with Seek Bar:**

```dart
// In PlaybackScreen seek bar
Slider(
  value: position.inMilliseconds.toDouble(),
  max: duration.inMilliseconds.toDouble(),
  onChangeStart: (_) {
    // Suspend prefetch while user is dragging
    ref.read(prefetchResumeControllerProvider).suspend();
  },
  onChanged: (value) {
    // Seek to position - don't restart timer on each change
    controller.seek(Duration(milliseconds: value.toInt()));
  },
  onChangeEnd: (_) {
    // User released seek bar - resume immediately
    ref.read(prefetchResumeControllerProvider).resumeImmediately();
  },
)
```

**Testing Strategy:**
- Unit tests for rapid seek detection
- Unit tests for timer cancellation
- Integration tests verifying prefetch doesn't run during active seek

---

### F3. No Configuration for SmartSynthesisManager Strategy

**Current State:**
- `EngineConfig` abstract with hardcoded values
- No way to override per-instance

**Problem:**
- Can't tune synthesis strategy for specific books or devices
- Single strategy doesn't fit all use cases (short vs long audiobooks)
- No hook for future ML-based strategy optimization

**Root Cause Analysis:**
The original design assumed one strategy works for all books. In reality:
- Short books (< 1 hour) can prefetch everything upfront
- Long books need streaming/incremental prefetch
- Users with fast devices want aggressive synthesis
- Battery-conscious users want minimal background work

**Proposed Solution:**

```dart
/// Strategy interface for synthesis behavior.
/// 
/// Implementations define how synthesis decisions are made:
/// - When to start prefetching
/// - How many segments to synthesize
/// - When to stop and conserve resources
abstract class SynthesisStrategy {
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
    final type = json['type'] as String;
    return switch (type) {
      'adaptive' => AdaptiveSynthesisStrategy.fromJson(json),
      'aggressive' => AggressiveSynthesisStrategy.fromJson(json),
      'conservative' => ConservativeSynthesisStrategy.fromJson(json),
      _ => AdaptiveSynthesisStrategy(),
    };
  }
}

/// Default adaptive strategy that balances quality and resources.
class AdaptiveSynthesisStrategy implements SynthesisStrategy {
  int _preSynthesizeCount;
  double _avgRtf = 0.5;
  int _completedCount = 0;
  
  AdaptiveSynthesisStrategy({int preSynthesizeCount = 3}) 
      : _preSynthesizeCount = preSynthesizeCount;
  
  @override
  int get preSynthesizeCount => _preSynthesizeCount;
  
  @override
  int get maxConcurrency => 1; // Sequential by default
  
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
    // Update running RTF average
    final rtf = synthesisTime.inMilliseconds / audioDuration.inMilliseconds;
    _completedCount++;
    _avgRtf = (_avgRtf * (_completedCount - 1) + rtf) / _completedCount;
    
    // Dynamically adjust preSynthesizeCount based on observed RTF
    if (_completedCount >= 5) {
      if (_avgRtf < 0.3) {
        _preSynthesizeCount = 5; // Fast device - synthesize more ahead
      } else if (_avgRtf > 0.8) {
        _preSynthesizeCount = 2; // Slow device - be conservative
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
    final strategy = AdaptiveSynthesisStrategy(
      preSynthesizeCount: json['preSynthesizeCount'] as int? ?? 3,
    );
    strategy._avgRtf = json['avgRtf'] as double? ?? 0.5;
    strategy._completedCount = json['completedCount'] as int? ?? 0;
    return strategy;
  }
}

/// Aggressive strategy for fast devices or when connected to power.
class AggressiveSynthesisStrategy implements SynthesisStrategy {
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
    // Always prefetch if there's work to do
    return remainingSegments > 0 && bufferedMs < 300000; // 5 min buffer
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
}

/// Conservative strategy for battery saving.
class ConservativeSynthesisStrategy implements SynthesisStrategy {
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
  }) {}
  
  @override
  Map<String, dynamic> toJson() => {'type': 'conservative'};
  
  factory ConservativeSynthesisStrategy.fromJson(Map<String, dynamic> json) =>
      ConservativeSynthesisStrategy();
}

/// SmartSynthesisManager with pluggable strategy.
class SmartSynthesisManager {
  SynthesisStrategy _strategy;
  
  SmartSynthesisManager({
    SynthesisStrategy? strategy,
  }) : _strategy = strategy ?? AdaptiveSynthesisStrategy();
  
  SynthesisStrategy get strategy => _strategy;
  
  /// Update strategy at runtime (e.g., when charging state changes).
  void setStrategy(SynthesisStrategy newStrategy) {
    developer.log('SmartSynthesisManager: Strategy changed to ${newStrategy.runtimeType}');
    _strategy = newStrategy;
  }
  
  /// Auto-select strategy based on device state.
  void autoSelectStrategy({
    required bool isCharging,
    required bool isLowPowerMode,
    required double measuredRtf,
  }) {
    if (isLowPowerMode) {
      setStrategy(ConservativeSynthesisStrategy());
    } else if (isCharging && measuredRtf < 0.5) {
      setStrategy(AggressiveSynthesisStrategy());
    } else {
      setStrategy(AdaptiveSynthesisStrategy());
    }
  }
}
```

**Integration Points:**
1. `SmartSynthesisManager` uses strategy for synthesis decisions
2. `BufferScheduler` consults strategy for prefetch decisions
3. Battery/charging state changes trigger strategy auto-selection
4. User can override via Settings

**Testing Strategy:**
- Unit tests for each strategy's decision logic
- Property-based tests for RTF adaptation
- Integration tests for strategy switching

---

### F4. Cache Budget Not Configurable at Runtime

**Current State:**
- `CacheBudget` defaults: 500 MB max, 7 days max age
- Can't adjust based on available storage

**Problem:**
- Device with 256 GB might want larger cache for synthesized audio
- Device with limited storage needs smaller cache
- Users can't trade storage for offline capability (pre-synthesized chapters)
- No auto-adjustment when device runs low on storage

**Root Cause Analysis:**
The cache budget was set based on conservative estimates. This cache stores locally synthesized audio (generated on-device via ONNX inference), not downloaded content. However:
- Modern devices often have 128+ GB storage
- Users may want to cache entire audiobooks (pre-synthesize) for smoother playback
- System may notify app when storage is low (platform events)

**Proposed Solution:**

```dart
/// Runtime-configurable cache manager with auto-tuning.
/// 
/// Manages the cache of locally synthesized audio segments. All audio is
/// generated on-device via ONNX Runtime inference - there is no network
/// dependency for synthesis operations.
/// 
/// Extends the base IntelligentCacheManager with:
/// - Runtime budget updates
/// - Auto-configuration based on available storage
/// - Low storage pressure handling
/// - Observability for cache operations
class ConfigurableCacheManager {
  CacheBudget _budget;
  final Directory _cacheDir;
  final StoragePressureMonitor _storageMonitor;
  
  // Observability
  final List<CacheEvent> _recentEvents = [];
  static const int _maxEvents = 100;
  
  ConfigurableCacheManager({
    required Directory cacheDir,
    CacheBudget? initialBudget,
    StoragePressureMonitor? storageMonitor,
  })  : _cacheDir = cacheDir,
        _budget = initialBudget ?? const CacheBudget(),
        _storageMonitor = storageMonitor ?? StoragePressureMonitor() {
    // Listen for storage pressure events
    _storageMonitor.onPressureChanged.listen(_handleStoragePressure);
  }
  
  CacheBudget get budget => _budget;
  List<CacheEvent> get recentEvents => List.unmodifiable(_recentEvents);
  
  /// Update budget at runtime.
  /// 
  /// If new budget is smaller, triggers immediate pruning.
  /// Logs the change for debugging.
  Future<void> updateBudget(CacheBudget newBudget) async {
    final oldBudget = _budget;
    _budget = newBudget;
    
    _logEvent(CacheEvent(
      type: CacheEventType.budgetChanged,
      details: 'Budget changed: ${oldBudget.maxSizeBytes ~/ 1024 ~/ 1024}MB -> '
          '${newBudget.maxSizeBytes ~/ 1024 ~/ 1024}MB',
    ));
    
    developer.log('CacheManager: Budget updated to ${newBudget.maxSizeBytes ~/ 1024 ~/ 1024}MB');
    
    // Prune if new budget is smaller
    if (newBudget.maxSizeBytes < oldBudget.maxSizeBytes) {
      await pruneToFit();
    }
  }
  
  /// Auto-configure budget based on available device storage.
  /// 
  /// Strategy:
  /// - Use up to 10% of free space
  /// - Minimum 100 MB
  /// - Maximum 4 GB
  /// - Consider existing cache size
  Future<void> autoConfigure() async {
    final available = await _getAvailableStorage();
    final currentSize = await _getCurrentCacheSize();
    
    // Calculate suggested budget
    int suggestedBytes = available ~/ 10; // 10% of free space
    
    // Apply bounds
    suggestedBytes = suggestedBytes.clamp(
      100 * 1024 * 1024,    // Min 100 MB
      4 * 1024 * 1024 * 1024, // Max 4 GB
    );
    
    // If cache is already larger than suggested, don't shrink dramatically
    // (user may have intentionally cached content)
    if (currentSize > suggestedBytes && currentSize < suggestedBytes * 2) {
      suggestedBytes = currentSize;
    }
    
    final suggestedBudget = CacheBudget(
      maxSizeBytes: suggestedBytes,
      maxAgeDays: _budget.maxAgeDays, // Preserve existing max age
    );
    
    await updateBudget(suggestedBudget);
    
    _logEvent(CacheEvent(
      type: CacheEventType.autoConfigure,
      details: 'Auto-configured: available=${available ~/ 1024 ~/ 1024}MB, '
          'suggested=${suggestedBytes ~/ 1024 ~/ 1024}MB',
    ));
  }
  
  /// Prune cache to fit within current budget.
  /// 
  /// Deletion order:
  /// 1. Expired entries (older than maxAgeDays)
  /// 2. Least recently accessed entries
  Future<PruneResult> pruneToFit() async {
    final beforeSize = await _getCurrentCacheSize();
    var deletedCount = 0;
    var deletedBytes = 0;
    
    // Step 1: Delete expired entries
    final expiredResult = await _deleteExpiredEntries();
    deletedCount += expiredResult.count;
    deletedBytes += expiredResult.bytes;
    
    // Step 2: If still over budget, delete LRU entries
    var currentSize = beforeSize - deletedBytes;
    if (currentSize > _budget.maxSizeBytes) {
      final lruResult = await _deleteLruEntries(
        targetSize: _budget.maxSizeBytes,
        currentSize: currentSize,
      );
      deletedCount += lruResult.count;
      deletedBytes += lruResult.bytes;
    }
    
    final result = PruneResult(
      deletedCount: deletedCount,
      deletedBytes: deletedBytes,
      beforeSize: beforeSize,
      afterSize: beforeSize - deletedBytes,
    );
    
    _logEvent(CacheEvent(
      type: CacheEventType.pruned,
      details: 'Pruned: deleted ${result.deletedCount} entries, '
          'freed ${result.deletedBytes ~/ 1024}KB',
    ));
    
    developer.log('CacheManager: Pruned $deletedCount entries, '
        'freed ${deletedBytes ~/ 1024}KB');
    
    return result;
  }
  
  /// Handle storage pressure events from the platform.
  void _handleStoragePressure(StoragePressureLevel level) {
    developer.log('CacheManager: Storage pressure changed to $level');
    
    switch (level) {
      case StoragePressureLevel.none:
        // Could restore budget to previous level
        break;
      case StoragePressureLevel.moderate:
        // Reduce budget by 25%
        updateBudget(CacheBudget(
          maxSizeBytes: (_budget.maxSizeBytes * 0.75).round(),
          maxAgeDays: _budget.maxAgeDays,
        ));
        break;
      case StoragePressureLevel.critical:
        // Reduce to minimum viable cache
        updateBudget(const CacheBudget(
          maxSizeBytes: 100 * 1024 * 1024, // 100 MB
          maxAgeDays: 1,
        ));
        break;
    }
  }
  
  void _logEvent(CacheEvent event) {
    _recentEvents.add(event);
    if (_recentEvents.length > _maxEvents) {
      _recentEvents.removeAt(0);
    }
  }
  
  Future<int> _getAvailableStorage() async {
    // Platform-specific implementation
    // Uses path_provider and platform channels
    throw UnimplementedError();
  }
  
  Future<int> _getCurrentCacheSize() async {
    // Sum of all files in cache directory
    throw UnimplementedError();
  }
  
  Future<_DeleteResult> _deleteExpiredEntries() async {
    throw UnimplementedError();
  }
  
  Future<_DeleteResult> _deleteLruEntries({
    required int targetSize,
    required int currentSize,
  }) async {
    throw UnimplementedError();
  }
}

/// Immutable cache budget configuration.
class CacheBudget {
  final int maxSizeBytes;
  final int maxAgeDays;
  
  const CacheBudget({
    this.maxSizeBytes = 500 * 1024 * 1024, // 500 MB
    this.maxAgeDays = 7,
  });
  
  CacheBudget copyWith({
    int? maxSizeBytes,
    int? maxAgeDays,
  }) => CacheBudget(
    maxSizeBytes: maxSizeBytes ?? this.maxSizeBytes,
    maxAgeDays: maxAgeDays ?? this.maxAgeDays,
  );
}

/// Result of a prune operation.
class PruneResult {
  final int deletedCount;
  final int deletedBytes;
  final int beforeSize;
  final int afterSize;
  
  const PruneResult({
    required this.deletedCount,
    required this.deletedBytes,
    required this.beforeSize,
    required this.afterSize,
  });
}

/// Cache event for observability.
class CacheEvent {
  final CacheEventType type;
  final String details;
  final DateTime timestamp;
  
  CacheEvent({
    required this.type,
    required this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum CacheEventType {
  budgetChanged,
  autoConfigure,
  pruned,
  entryAdded,
  entryDeleted,
  storagePressure,
}

/// Platform storage pressure levels.
enum StoragePressureLevel {
  none,
  moderate,
  critical,
}

/// Monitors storage pressure from platform.
class StoragePressureMonitor {
  final _controller = StreamController<StoragePressureLevel>.broadcast();
  
  Stream<StoragePressureLevel> get onPressureChanged => _controller.stream;
  
  /// Called from platform channel when storage pressure changes.
  void reportPressure(StoragePressureLevel level) {
    _controller.add(level);
  }
  
  void dispose() {
    _controller.close();
  }
}

class _DeleteResult {
  final int count;
  final int bytes;
  _DeleteResult(this.count, this.bytes);
}
```

**Platform Integration:**

For Android, storage pressure can be detected via:
```kotlin
// In MainActivity or a dedicated service
override fun onTrimMemory(level: Int) {
    when (level) {
        TRIM_MEMORY_RUNNING_LOW, TRIM_MEMORY_RUNNING_CRITICAL -> {
            methodChannel.invokeMethod("storagePressure", "critical")
        }
        TRIM_MEMORY_RUNNING_MODERATE -> {
            methodChannel.invokeMethod("storagePressure", "moderate")  
        }
    }
}
```

**Testing Strategy:**
- Unit tests for budget changes and pruning logic
- Integration tests simulating storage pressure
- Property-based tests for auto-configuration bounds

---

### F5. Prefetch Concurrency Ignored

**Current State:**
- `prefetchConcurrency = 1` (unused)
- `DeviceEngineConfig.prefetchConcurrency` exists but not connected
- `SynthesisModeConfig.concurrencyLimit` exists but not used

**Problem:**
- Three separate sources of truth for concurrency
- None are actually used in prefetch loops
- Wasted potential on multi-core devices

**Root Cause Analysis:**
Parallel synthesis was considered but never implemented due to:
1. Complexity of coordinating concurrent synthesis
2. Potential for OOM with multiple audio buffers in memory
3. Uncertainty about thread-safety of TTS engines

**Risk Analysis:**
Parallel synthesis introduces risks that must be mitigated:
- **OOM Risk**: Multiple segments in memory simultaneously
- **Race Conditions**: Concurrent access to shared resources
- **Resource Contention**: Multiple ONNX inference competing for GPU/NPU

**Proposed Solution:**

```dart
/// Parallel synthesis orchestrator with memory-aware scheduling.
/// 
/// Coordinates parallel on-device TTS synthesis using ONNX Runtime.
/// All synthesis is performed locally - no network calls involved.
/// 
/// Key safety features:
/// - Memory limit before starting new synthesis
/// - Immediate streaming to cache (don't hold results in memory)
/// - Graceful degradation under memory pressure
/// - Single source of truth for concurrency configuration
class ParallelSynthesisOrchestrator {
  final int _maxConcurrency;
  final ConfigurableCacheManager _cacheManager;
  final MemoryMonitor _memoryMonitor;
  
  // Semaphore for concurrency control
  late final _Semaphore _semaphore;
  
  // Track in-flight synthesis operations
  final Set<String> _inFlightSegments = {};
  
  // Memory threshold for starting new synthesis (bytes)
  static const int _memoryThresholdBytes = 200 * 1024 * 1024; // 200 MB
  
  ParallelSynthesisOrchestrator({
    required int maxConcurrency,
    required ConfigurableCacheManager cacheManager,
    required MemoryMonitor memoryMonitor,
  })  : _maxConcurrency = maxConcurrency.clamp(1, 4),
        _cacheManager = cacheManager,
        _memoryMonitor = memoryMonitor,
        _semaphore = _Semaphore(maxConcurrency.clamp(1, 4));
  
  int get maxConcurrency => _maxConcurrency;
  int get activeCount => _inFlightSegments.length;
  
  /// Synthesize multiple segments with controlled parallelism.
  /// 
  /// Memory-safe: checks memory before starting each synthesis.
  /// Results are streamed to cache immediately, not held in memory.
  Future<List<SynthesisResult>> synthesizeSegments({
    required List<TextSegment> segments,
    required TtsEngine engine,
    required VoiceConfig voice,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (segments.isEmpty) return [];
    
    // For single segment or concurrency=1, use simple sequential
    if (segments.length == 1 || _maxConcurrency == 1) {
      return _synthesizeSequential(segments, engine, voice, onProgress);
    }
    
    // Parallel synthesis with memory-aware scheduling
    return _synthesizeParallel(segments, engine, voice, onProgress);
  }
  
  Future<List<SynthesisResult>> _synthesizeSequential(
    List<TextSegment> segments,
    TtsEngine engine,
    VoiceConfig voice,
    void Function(int, int)? onProgress,
  ) async {
    final results = <SynthesisResult>[];
    
    for (var i = 0; i < segments.length; i++) {
      final result = await _synthesizeOne(segments[i], engine, voice);
      results.add(result);
      onProgress?.call(i + 1, segments.length);
    }
    
    return results;
  }
  
  Future<List<SynthesisResult>> _synthesizeParallel(
    List<TextSegment> segments,
    TtsEngine engine,
    VoiceConfig voice,
    void Function(int, int)? onProgress,
  ) async {
    final results = List<SynthesisResult?>.filled(segments.length, null);
    var completedCount = 0;
    final completer = Completer<List<SynthesisResult>>();
    
    // Process segments with controlled parallelism
    for (var i = 0; i < segments.length; i++) {
      final index = i;
      
      // Fire-and-forget with semaphore
      unawaited(_synthesizeWithSemaphore(
        index: index,
        segment: segments[index],
        engine: engine,
        voice: voice,
      ).then((result) {
        results[index] = result;
        completedCount++;
        onProgress?.call(completedCount, segments.length);
        
        if (completedCount == segments.length) {
          completer.complete(results.cast<SynthesisResult>());
        }
      }).catchError((error) {
        results[index] = SynthesisResult.error(segments[index].id, error);
        completedCount++;
        onProgress?.call(completedCount, segments.length);
        
        if (completedCount == segments.length) {
          completer.complete(results.cast<SynthesisResult>());
        }
      }));
    }
    
    return completer.future;
  }
  
  Future<SynthesisResult> _synthesizeWithSemaphore({
    required int index,
    required TextSegment segment,
    required TtsEngine engine,
    required VoiceConfig voice,
  }) async {
    // Wait for semaphore slot
    await _semaphore.acquire();
    
    try {
      // Check memory before starting
      if (!await _memoryMonitor.hasSufficientMemory(_memoryThresholdBytes)) {
        developer.log('ParallelSynthesis: Memory pressure, waiting for slot $index');
        
        // Wait until memory is available or timeout
        final memoryAvailable = await _waitForMemory(
          threshold: _memoryThresholdBytes,
          timeout: const Duration(seconds: 30),
        );
        
        if (!memoryAvailable) {
          throw SynthesisException('Insufficient memory for synthesis');
        }
      }
      
      return await _synthesizeOne(segment, engine, voice);
    } finally {
      _semaphore.release();
    }
  }
  
  Future<SynthesisResult> _synthesizeOne(
    TextSegment segment,
    TtsEngine engine,
    VoiceConfig voice,
  ) async {
    final segmentId = segment.id;
    _inFlightSegments.add(segmentId);
    
    try {
      final stopwatch = Stopwatch()..start();
      
      // Synthesize to byte stream
      final audioBytes = await engine.synthesize(
        text: segment.text,
        voice: voice,
      );
      
      stopwatch.stop();
      
      // Immediately write to cache (don't hold in memory)
      final cacheKey = _generateCacheKey(segment, voice);
      await _cacheManager.writeAudio(cacheKey, audioBytes);
      
      // Return result with cache reference, not audio data
      return SynthesisResult.success(
        segmentId: segmentId,
        cacheKey: cacheKey,
        durationMs: _estimateDuration(audioBytes.length),
        synthesisTimeMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      _inFlightSegments.remove(segmentId);
    }
  }
  
  Future<bool> _waitForMemory({
    required int threshold,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(deadline)) {
      if (await _memoryMonitor.hasSufficientMemory(threshold)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    return false;
  }
  
  String _generateCacheKey(TextSegment segment, VoiceConfig voice) {
    return '${voice.id}_${segment.hashCode}';
  }
  
  int _estimateDuration(int audioBytes) {
    // Rough estimate: 16kHz, 16-bit mono = 32KB per second
    return (audioBytes / 32000 * 1000).round();
  }
}

/// Simple semaphore for concurrency control.
class _Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final Queue<Completer<void>> _waiters = Queue();
  
  _Semaphore(this._maxCount);
  
  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }
    
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }
  
  void release() {
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      waiter.complete();
    } else {
      _currentCount--;
    }
  }
}

/// Synthesis result that references cached audio.
class SynthesisResult {
  final String segmentId;
  final String? cacheKey;
  final int? durationMs;
  final int? synthesisTimeMs;
  final Object? error;
  final bool isSuccess;
  
  SynthesisResult.success({
    required this.segmentId,
    required this.cacheKey,
    required this.durationMs,
    required this.synthesisTimeMs,
  })  : error = null,
        isSuccess = true;
  
  SynthesisResult.error(this.segmentId, this.error)
      : cacheKey = null,
        durationMs = null,
        synthesisTimeMs = null,
        isSuccess = false;
}

/// Monitors memory availability.
abstract class MemoryMonitor {
  /// Check if there's at least [bytes] of memory available.
  Future<bool> hasSufficientMemory(int bytes);
  
  /// Get current memory info.
  Future<MemoryInfo> getMemoryInfo();
}

/// Memory information snapshot.
class MemoryInfo {
  final int availableBytes;
  final int totalBytes;
  final int usedBytes;
  
  MemoryInfo({
    required this.availableBytes,
    required this.totalBytes,
    required this.usedBytes,
  });
  
  double get usagePercent => usedBytes / totalBytes;
}

class SynthesisException implements Exception {
  final String message;
  SynthesisException(this.message);
  @override
  String toString() => 'SynthesisException: $message';
}
```

**Concurrency Source of Truth:**
Remove duplicate configuration and establish single source:

```dart
// REMOVE from PlaybackConfig:
// - prefetchConcurrency (unused)

// KEEP and USE from DeviceEngineConfig:
// - prefetchConcurrency

// Integration in BufferScheduler:
class BufferScheduler {
  late final ParallelSynthesisOrchestrator _synthesizer;
  
  void initialize(DeviceEngineConfig config) {
    _synthesizer = ParallelSynthesisOrchestrator(
      maxConcurrency: config.prefetchConcurrency, // Single source of truth
      cacheManager: _cacheManager,
      memoryMonitor: _memoryMonitor,
    );
  }
}
```

**Testing Strategy:**
- Unit tests with mock memory monitor
- Stress tests with varying concurrency levels
- Memory profiling on real devices
- Test graceful degradation under OOM conditions

---

## Related Issues to Include

### E2. Voice Change Mid-Prefetch

**Connection to F1/F3:** When voice changes, prefetch window and strategy need recalculation.

**Proposed Solution:**

```dart
/// Handles voice change events during playback.
/// 
/// Voice changes invalidate cached synthesis since voice is part of the cache key.
/// This class coordinates cache cleanup and scheduler reset.
class VoiceChangeHandler {
  final ConfigurableCacheManager _cacheManager;
  final BufferScheduler _scheduler;
  final SmartSynthesisManager _synthesisManager;
  
  VoiceChangeHandler({
    required ConfigurableCacheManager cacheManager,
    required BufferScheduler scheduler,
    required SmartSynthesisManager synthesisManager,
  })  : _cacheManager = cacheManager,
        _scheduler = scheduler,
        _synthesisManager = synthesisManager;
  
  /// Call when voice is changed by user.
  Future<void> onVoiceChanged({
    required VoiceConfig oldVoice,
    required VoiceConfig newVoice,
    required int currentPosition,
  }) async {
    developer.log('VoiceChangeHandler: Voice changed from ${oldVoice.id} to ${newVoice.id}');
    
    // 1. Suspend prefetch immediately
    _scheduler.suspend();
    
    // 2. Clear cache entries with old voice prefix
    await _cacheManager.deleteByPrefix(oldVoice.id);
    
    // 3. Reset synthesis context
    _synthesisManager.resetContext();
    
    // 4. Start prefetch from current position with new voice
    await _scheduler.startFromPosition(
      position: currentPosition,
      voice: newVoice,
    );
    
    developer.log('VoiceChangeHandler: Prefetch restarted with new voice');
  }
}
```

### E3. Out-of-Memory During Prefetch

**Connection to F1/F4:** OOM indicates prefetch is too aggressive or cache too large.

**Problem with Catching OOM in Dart:**
Dart's `OutOfMemoryError` is often unrecoverable. The VM may be in an inconsistent state.

**Proposed Solution - Platform-Based Memory Pressure:**

```dart
/// Memory pressure handler using platform callbacks.
/// 
/// Instead of catching OOM (which is unreliable), we proactively respond
/// to memory pressure signals from the platform.
class MemoryPressureHandler {
  final AdaptivePrefetchConfig _prefetchConfig;
  final ConfigurableCacheManager _cacheManager;
  final BufferScheduler _scheduler;
  
  // Rollback state
  int? _previousPrefetchWindow;
  CacheBudget? _previousBudget;
  
  MemoryPressureHandler({
    required AdaptivePrefetchConfig prefetchConfig,
    required ConfigurableCacheManager cacheManager,
    required BufferScheduler scheduler,
  })  : _prefetchConfig = prefetchConfig,
        _cacheManager = cacheManager,
        _scheduler = scheduler;
  
  /// Called from platform channel when memory pressure changes.
  Future<void> onMemoryPressure(MemoryPressure level) async {
    developer.log('MemoryPressureHandler: Pressure level = $level');
    
    switch (level) {
      case MemoryPressure.none:
        // Optionally restore previous settings
        await _tryRestorePrevious();
        break;
        
      case MemoryPressure.moderate:
        // Save current settings for potential rollback
        _saveCurrent();
        
        // Reduce prefetch window by 50%
        _scheduler.temporarilyReducePrefetch(factor: 0.5);
        
        // Trigger cache pruning
        await _cacheManager.pruneToFit();
        break;
        
      case MemoryPressure.critical:
        // Save if not already saved
        _saveCurrent();
        
        // Aggressive reduction
        _scheduler.temporarilyReducePrefetch(factor: 0.25);
        
        // Emergency cache clear (keep only current track)
        await _cacheManager.emergencyClear(keepCurrent: true);
        
        // Report for metrics
        developer.log('MemoryPressureHandler: Emergency memory recovery triggered');
        break;
    }
  }
  
  void _saveCurrent() {
    _previousPrefetchWindow ??= _prefetchConfig.currentWindow;
    _previousBudget ??= _cacheManager.budget;
  }
  
  Future<void> _tryRestorePrevious() async {
    if (_previousPrefetchWindow != null) {
      _scheduler.restorePrefetchWindow(_previousPrefetchWindow!);
      _previousPrefetchWindow = null;
    }
    
    if (_previousBudget != null) {
      await _cacheManager.updateBudget(_previousBudget!);
      _previousBudget = null;
    }
    
    developer.log('MemoryPressureHandler: Settings restored');
  }
}
```

**Android Platform Integration:**

```kotlin
// In MainActivity.kt
class MainActivity : FlutterActivity() {
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        
        val flutterLevel = when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> "critical"
            
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> "moderate"
            
            else -> "none"
        }
        
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, "app/memory")
                .invokeMethod("memoryPressure", flutterLevel)
        }
    }
}
```

### E5. Rapid Rate Changes

**Connection to F3/F4:** Rate changes may invalidate cached audio.

**Proposed Solution:**

```dart
/// Handles playback rate changes.
/// 
/// If rateIndependentSynthesis is true (default), cached audio remains valid
/// since rate is applied at playback time, not synthesis time.
/// 
/// If false, rate is baked into synthesis and cache must be invalidated.
class RateChangeHandler {
  final RuntimePlaybackConfig _config;
  final ConfigurableCacheManager _cacheManager;
  final BufferScheduler _scheduler;
  
  // Debounce rapid rate changes
  Timer? _rateChangeDebounce;
  double _pendingRate = 1.0;
  
  RateChangeHandler({
    required RuntimePlaybackConfig config,
    required ConfigurableCacheManager cacheManager,
    required BufferScheduler scheduler,
  })  : _config = config,
        _cacheManager = cacheManager,
        _scheduler = scheduler;
  
  /// Call when user changes playback rate.
  void onRateChanged(double newRate) {
    _pendingRate = newRate;
    
    // Debounce: wait for rate changes to settle
    _rateChangeDebounce?.cancel();
    _rateChangeDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _applyRateChange(_pendingRate),
    );
  }
  
  Future<void> _applyRateChange(double rate) async {
    developer.log('RateChangeHandler: Applying rate change to $rate');
    
    // If rate-independent synthesis, no cache invalidation needed
    if (_config.rateIndependentSynthesis) {
      // Just update playback rate - cache stays valid
      return;
    }
    
    // Rate is baked into synthesis - must invalidate cache
    developer.log('RateChangeHandler: Clearing cache due to rate change');
    
    _scheduler.suspend();
    
    // Clear all cached audio (rate is part of the audio data)
    await _cacheManager.clearAll();
    
    // Restart synthesis with new rate
    _scheduler.restartWithRate(rate);
  }
  
  void dispose() {
    _rateChangeDebounce?.cancel();
  }
}
```

---

## Implementation Plan

### Phase 1: Foundation (1 sprint) ✅ COMPLETE

**Goal:** Establish the configuration persistence layer that all other phases depend on.

| Task | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| Create `RuntimePlaybackConfig` class with persistence | Medium | Critical | None |
| Create `RuntimeConfigNotifier` Riverpod provider | Low | Critical | RuntimePlaybackConfig |
| Add `updateBudget()` to CacheManager | Low | High | RuntimePlaybackConfig |
| Remove unused `PlaybackConfig.prefetchConcurrency` | Low | Medium | None |
| Add platform channel for memory pressure (Android) | Medium | High | None |
| Add platform channel for storage pressure (Android) | Medium | High | None |

**Deliverable:** Runtime-configurable cache budget with persistence across app restarts.

**Acceptance Criteria:**
- [x] Config persists to SharedPreferences
- [x] Config loads on app start
- [x] Config changes logged with before/after values
- [x] Cache budget can be updated at runtime
- [x] Budget changes trigger pruning when smaller

**Validation:**
```dart
// Test script
final config = await RuntimePlaybackConfig.load();
print('Initial: ${config.cacheBudgetBytes}');

final updated = config.copyWith(cacheBudgetBytes: 1024 * 1024 * 1024);
await updated.save();

final reloaded = await RuntimePlaybackConfig.load();
assert(reloaded.cacheBudgetBytes == 1024 * 1024 * 1024);
```

### Phase 2: Adaptive Prefetch (1-2 sprints) ✅ COMPLETE

**Goal:** Replace static prefetch window with intelligent, context-aware calculation.

| Task | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| Implement `AdaptivePrefetchConfig` | Medium | High | Phase 1 |
| Implement `PrefetchResumeController` | Medium | Medium | Phase 1 |
| Integrate with `BufferScheduler` | Medium | High | AdaptivePrefetchConfig |
| Add `resumeImmediately()` to seek bar | Low | Low | PrefetchResumeController |
| Add MemoryPressure enum and platform channel | Medium | High | Platform channels |
| Implement rapid seek detection | Low | Low | PrefetchResumeController |

**Deliverable:** Prefetch window adapts to queue length, RTF, charging state, and memory pressure.

**Acceptance Criteria:**
- [x] Prefetch window never exceeds remaining queue length
- [x] Fast RTF (< 0.3) increases prefetch window by 1.5x
- [x] Charging increases prefetch window by 1.25x
- [x] Memory pressure reduces prefetch window
- [x] Resume delay configurable via RuntimePlaybackConfig
- [x] Manual resume works from seek bar onChangeEnd

**Validation:**
- Test with 3-segment chapter → window ≤ 3
- Test on fast device (RTF 0.2) → window increases
- Test on battery → window normal; charging → window larger

### Phase 3: Synthesis Strategy (1 sprint) ✅ COMPLETE

**Goal:** Replace hardcoded synthesis behavior with pluggable strategy pattern.

| Task | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| Define `SynthesisStrategy` interface | Low | High | None |
| Implement `AdaptiveSynthesisStrategy` | Medium | High | Interface |
| Implement `AggressiveSynthesisStrategy` | Low | Medium | Interface |
| Implement `ConservativeSynthesisStrategy` | Low | Medium | Interface |
| Integrate with `SmartSynthesisManager` | Medium | High | Strategies |
| Add auto-selection based on device state | Medium | Medium | All strategies |

**Deliverable:** Synthesis strategy can be changed at runtime based on device state.

**Acceptance Criteria:**
- [x] Strategy persists across restarts (via RuntimePlaybackConfig)
- [x] Auto-selection considers charging, low-power mode, RTF
- [x] Adaptive strategy learns from observed RTF
- [x] Strategy change logged for debugging

### Phase 4: Parallel Synthesis (2 sprints) ✅ COMPLETE

**Goal:** Enable optional parallel synthesis on capable devices with memory safety.

| Task | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| Implement `_Semaphore` for concurrency control | Low | High | None |
| Implement `MemoryMonitor` abstraction | Medium | High | Platform channels |
| Implement `ParallelSynthesisOrchestrator` | High | High | Semaphore, MemoryMonitor |
| Integrate memory-aware scheduling | High | High | Orchestrator |
| Wire `DeviceEngineConfig.prefetchConcurrency` | Medium | Medium | Orchestrator |
| Add feature flag for parallel synthesis | Low | High | None |

**Deliverable:** Optional parallel synthesis on capable devices with memory safety.

**Risk Mitigation:**
- Gate behind feature flag (disabled by default)
- Memory check before each synthesis start
- Immediate streaming to cache (no in-memory accumulation)
- Graceful degradation to sequential on memory pressure

**Acceptance Criteria:**
- [x] Parallel synthesis respects semaphore limit
- [x] Memory pressure pauses new synthesis starts
- [x] Results stream to cache immediately
- [x] Works correctly with concurrency 1 (sequential)
- [x] No memory growth with increasing concurrency

### Phase 5: Edge Case Handlers (1 sprint) ✅ COMPLETE

**Goal:** Handle voice changes, memory pressure, and rate changes gracefully.

| Task | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| Implement `VoiceChangeHandler` | Medium | High | Cache, Scheduler |
| Implement `MemoryPressureHandler` with rollback | Medium | High | Phase 2 |
| Implement `RateChangeHandler` with debounce | Low | Medium | Cache, Scheduler |
| Add rollback mechanism for auto-tuning | Medium | High | All handlers |
| Integration tests for edge cases | High | High | All handlers |

**Deliverable:** Graceful handling of voice changes, memory pressure, and rate changes.

**Implementation:**
- `VoiceChangeHandler`: Coordinates cancellation, context invalidation, and resynthesis
- `MemoryPressureHandler`: Handles moderate/critical pressure with recovery timer
- `RateChangeHandler`: Debounces rapid changes, handles rate-independent vs rate-dependent synthesis
- `AutoTuneRollback`: Snapshot-based rollback with performance degradation detection

**Rollback Strategy:**
```dart
// Auto-tuning rollback mechanism
class AutoTuneRollback {
  final List<ConfigSnapshot> _snapshots = [];
  static const int _maxSnapshots = 5;
  
  void saveSnapshot(RuntimePlaybackConfig config, String reason) {
    _snapshots.add(ConfigSnapshot(config, reason, DateTime.now()));
    if (_snapshots.length > _maxSnapshots) {
      _snapshots.removeAt(0);
    }
  }
  
  Future<void> rollbackIfDegraded({
    required PerformanceMetrics current,
    required PerformanceMetrics baseline,
  }) async {
    // Rollback if buffer underruns increased by >50%
    if (current.bufferUnderrunRate > baseline.bufferUnderrunRate * 1.5) {
      final previous = _snapshots.lastOrNull;
      if (previous != null) {
        developer.log('AutoTune: Rolling back due to degraded performance');
        await previous.config.save();
      }
    }
  }
}
```

### Phase 6: User Settings (1 sprint) ✅ COMPLETE

**Goal:** Expose appropriate controls to users who want fine-tuning.

| Task | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| Add cache size picker to Settings | Low | Medium | Phase 1 |
| Add cache max age picker | Low | Low | Phase 1 |
| Add "Auto-tune for this device" button | Low | Medium | Phase 1 |
| Add "Clear Cache" with confirmation | Low | Medium | Phase 1 |
| Add Advanced Settings section (collapsible) | Medium | Low | All phases |
| Add prefetch mode selector (Advanced) | Low | Low | Phase 2 |
| Add parallel synthesis toggle (Advanced) | Low | Low | Phase 4 |

**Deliverable:** Power user controls for cache and synthesis behavior.

**Acceptance Criteria:**
- [x] Default settings work without user intervention
- [x] Advanced settings hidden behind "Advanced" section
- [x] Each setting has explanatory subtitle
- [x] Changes apply immediately
- [x] "Reset to Defaults" available

---

## Settings UI Design

### Cache Settings
```
┌─────────────────────────────────────────────────────────┐
│ Cache                                                    │
├─────────────────────────────────────────────────────────┤
│ Cache Size                                      [Auto ▼] │
│ Current: 342 MB / 500 MB                                 │
│ Options: Auto, 250 MB, 500 MB, 1 GB, 2 GB, 4 GB         │
├─────────────────────────────────────────────────────────┤
│ Cache Expiry                                  [7 days ▼] │
│ Older entries are automatically deleted                  │
│ Options: 3 days, 7 days, 14 days, 30 days, Never        │
├─────────────────────────────────────────────────────────┤
│ [Auto-tune for this device]                             │
│ Automatically configure based on available storage       │
├─────────────────────────────────────────────────────────┤
│ [Clear Cache]                                           │
│ Delete all cached audio (342 MB)                        │
└─────────────────────────────────────────────────────────┘
```

### Synthesis Settings (Advanced - Collapsed by Default)
```
┌─────────────────────────────────────────────────────────┐
│ ▶ Advanced Synthesis Settings                           │
└─────────────────────────────────────────────────────────┘

Expanded:
┌─────────────────────────────────────────────────────────┐
│ ▼ Advanced Synthesis Settings                           │
├─────────────────────────────────────────────────────────┤
│ Prefetch Mode                                [Adaptive▼] │
│ How aggressively to prepare upcoming audio               │
│ • Adaptive: Balance quality and resources (recommended)  │
│ • Aggressive: Prepare more audio ahead                   │
│ • Conservative: Minimize background work                 │
│ • Off: Only synthesize current segment                   │
├─────────────────────────────────────────────────────────┤
│ Parallel Synthesis                              [Auto ▼] │
│ Use multiple threads for synthesis                       │
│ Options: Auto, 1, 2, 4                                   │
│ ⚠️ Higher values use more memory                         │
├─────────────────────────────────────────────────────────┤
│ Resume Delay                                    [500ms▼] │
│ Wait before resuming synthesis after seeking             │
│ Options: 250ms, 500ms, 1000ms                           │
├─────────────────────────────────────────────────────────┤
│ [Reset to Defaults]                                     │
└─────────────────────────────────────────────────────────┘
```

### Debug Settings (Developer Mode Only)
```
┌─────────────────────────────────────────────────────────┐
│ Debug Information (Developer Mode)                      │
├─────────────────────────────────────────────────────────┤
│ Current RTF: 0.32 (synthesis 3x faster than playback)   │
│ Memory Pressure: None                                    │
│ Storage Available: 45.2 GB                              │
│ Cache Entries: 127                                       │
│ Active Synthesis: 0                                      │
├─────────────────────────────────────────────────────────┤
│ [Export Config Snapshot]                                │
│ [View Recent Cache Events]                              │
└─────────────────────────────────────────────────────────┘
```

---

## Success Metrics

### Quantitative Metrics

| Metric | Baseline | Target | Measurement Method |
|--------|----------|--------|-------------------|
| Cache utilization | Unknown | 60-80% of budget | `cacheSize / cacheBudget` |
| Buffer underruns | Unknown | < 1% of sessions | Count underruns / total playback sessions |
| Battery impact | Current impl | ≤ 100% of current | Power profiling comparison |
| Memory pressure events | Unknown | < 5% of sessions | Platform callbacks |
| Config persistence success | N/A | > 99.9% | Load success rate |

### Qualitative Metrics

| Metric | Success Criteria |
|--------|-----------------|
| Settings discoverability | Users can find cache settings within 30 seconds |
| Settings comprehension | Users understand what each setting does (via subtitles) |
| Advanced settings isolation | Casual users don't accidentally change advanced settings |
| Default behavior | No regressions for users who don't change settings |

### Instrumentation Plan

```dart
// Add these analytics events
class ConfigAnalytics {
  static void logConfigChange(String setting, dynamic oldValue, dynamic newValue) {
    // Log to analytics service
  }
  
  static void logAutoTuneApplied(CacheBudget suggested) {
    // Track auto-tune usage
  }
  
  static void logRollbackTriggered(String reason) {
    // Track rollback frequency
  }
  
  static void logMemoryPressure(MemoryPressure level) {
    // Track memory pressure frequency
  }
}
```

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Complexity increase** | High | Medium | Default to current behavior; advanced settings hidden; extensive documentation |
| **Parallel synthesis OOM** | Medium | High | Gate behind feature flag; memory check before each synthesis; immediate streaming to cache |
| **Parallel synthesis race conditions** | Medium | High | Comprehensive unit tests; semaphore-based coordination; immutable result objects |
| **User confusion** | Medium | Low | Clear explanations via subtitles; "Auto" as default; Reset to Defaults button |
| **Device-specific issues** | Medium | Medium | Comprehensive device profiling; graceful degradation; rollback mechanism |
| **Config corruption** | Low | Medium | JSON validation on load; fallback to defaults on parse error; version migration |
| **Performance regression** | Low | High | A/B testing; rollback mechanism; baseline metrics before deployment |
| **Platform channel failures** | Low | Medium | Graceful degradation to conservative defaults; retry with exponential backoff |

### Contingency Plans

**If parallel synthesis causes widespread issues:**
1. Release hotfix that defaults to sequential synthesis
2. Add more comprehensive memory checking before synthesis
3. Reduce default concurrency limit

**If auto-tuning causes regressions:**
1. Rollback mechanism activates automatically based on local performance metrics
2. Users can reset to defaults via Settings
3. App update can change default configuration if needed

**If config persistence fails:**
1. Fallback to in-memory defaults
2. Log failure for debugging
3. Attempt re-save on next config change

---

## Open Questions (Resolved)

### 1. Should we expose RTF measurements to users?

**Decision:** Show only in "Developer Mode" settings section.

**Rationale:**
- RTF is a technical metric that most users won't understand
- Power users and developers will find it useful for debugging
- Showing in normal settings would add clutter

**Implementation:**
- Add "Developer Mode" toggle in About section
- When enabled, show Debug Information section in settings
- Include current RTF, memory pressure, cache stats

### 2. How granular should cache control be (per-book vs global)?

**Decision:** Start with global, add per-book as future enhancement.

**Rationale:**
- Global is simpler to implement and understand
- Per-book adds significant complexity (UI, persistence, pruning logic)
- Can be added later without breaking changes

**Future Enhancement Path:**
```dart
// Potential per-book cache config (not in initial implementation)
class BookCacheConfig {
  final String bookId;
  final bool keepCached;      // Prevent auto-pruning
  final int? maxSizeMb;       // Per-book limit
  final int? maxAgeDays;      // Per-book expiry
}
```

### 3. Should we auto-adjust settings based on error rates?

**Decision:** Yes, with user notification.

**Rationale:**
- Auto-adjustment improves experience on struggling devices
- Users should be informed when settings change automatically
- Rollback available if auto-adjustment causes problems

**Implementation:**
```dart
// Example notification
void notifyAutoAdjustment(String reason, String action) {
  showSnackBar(
    'Playback optimized: $action',
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () => rollbackLastAutoAdjustment(),
    ),
  );
}

// Example triggers
// - 3+ buffer underruns in 5 minutes → increase prefetch
// - Memory pressure critical → reduce prefetch, notify user
// - Synthesis consistently fast → suggest aggressive mode
```

---

## Testing Strategy

### Unit Tests

| Component | Test Cases |
|-----------|------------|
| `RuntimePlaybackConfig` | Serialization, defaults, copyWith, persistence |
| `AdaptivePrefetchConfig` | Boundary conditions, RTF multipliers, memory pressure |
| `PrefetchResumeController` | Debouncing, rapid seek detection, manual resume |
| `SynthesisStrategy` implementations | Decision logic, RTF adaptation |
| `ConfigurableCacheManager` | Budget changes, auto-configure, pruning |
| `ParallelSynthesisOrchestrator` | Semaphore, memory checks, error handling |
| `VoiceChangeHandler` | Cache invalidation, scheduler reset |
| `MemoryPressureHandler` | Level handling, rollback |

### Integration Tests

| Scenario | Validation |
|----------|------------|
| App restart | Config persists and loads correctly |
| Voice change during playback | Cache cleared, playback continues smoothly |
| Memory pressure during synthesis | Graceful degradation, no crash |
| Rapid seeking | No synthesis thrashing |
| Parallel synthesis | Results in correct order, no OOM |

### Device Testing Matrix

| Device Category | Test Focus |
|----------------|------------|
| Low-end (2GB RAM) | Memory pressure handling, conservative defaults |
| Mid-range (4GB RAM) | Balanced adaptive behavior |
| High-end (8GB+ RAM) | Aggressive mode, parallel synthesis |
| Low storage (< 10GB free) | Auto-configure, storage pressure |
| High storage (> 100GB free) | Large cache budget |

---

## References

- [improvement_opportunities.md](../../architecture/improvement_opportunities.md) - F1-F5, E2-E5
- [AUTO_TUNING_SYSTEM.md](../smart-audio-synth/AUTO_TUNING_SYSTEM.md) - Device profiling design
- [engine_config.dart](../../../packages/playback/lib/src/engine_config.dart) - DeviceEngineConfig

---

## Appendix A: Migration Guide

### For Existing Code

**Before (hardcoded):**
```dart
// Old pattern
final config = PlaybackConfig();
final prefetchWindow = config.maxPrefetchTracks; // Always 10
```

**After (runtime configurable):**
```dart
// New pattern
final runtimeConfig = ref.watch(runtimeConfigProvider).valueOrNull ?? RuntimePlaybackConfig();
final adaptivePrefetch = AdaptivePrefetchConfig(runtimeConfig);
final prefetchWindow = adaptivePrefetch.calculatePrefetchWindow(
  queueLength: queue.length,
  currentPosition: currentIndex,
  measuredRTF: synthesisManager.measuredRTF,
  mode: currentMode,
  isCharging: batteryState.isCharging,
  memoryPressure: memoryState.pressure,
);
```

### SharedPreferences Key

The configuration is stored under key `runtime_playback_config_v1`. If schema changes require migration, bump the version number and add migration logic in `RuntimePlaybackConfig.load()`.

---

## Appendix B: File Locations

| Component | Proposed Location |
|-----------|-------------------|
| `RuntimePlaybackConfig` | `lib/app/config/runtime_playback_config.dart` |
| `RuntimeConfigNotifier` | `lib/app/providers/config_providers.dart` |
| `AdaptivePrefetchConfig` | `packages/playback/lib/src/adaptive_prefetch.dart` |
| `PrefetchResumeController` | `packages/playback/lib/src/prefetch_resume.dart` |
| `SynthesisStrategy` | `packages/playback/lib/src/strategies/synthesis_strategy.dart` |
| `ConfigurableCacheManager` | `packages/playback/lib/src/cache/configurable_cache_manager.dart` |
| `ParallelSynthesisOrchestrator` | `packages/playback/lib/src/synthesis/parallel_orchestrator.dart` |
| `VoiceChangeHandler` | `packages/playback/lib/src/handlers/voice_change_handler.dart` |
| `MemoryPressureHandler` | `packages/playback/lib/src/handlers/memory_pressure_handler.dart` |
| `RateChangeHandler` | `packages/playback/lib/src/handlers/rate_change_handler.dart` |
| Settings UI | `lib/ui/screens/settings/playback_settings_section.dart` |
| Platform channels | `android/app/src/main/kotlin/.../MemoryPressureChannel.kt` |

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-24 | AI | Initial detailed plan with persistence, observability, rollback strategies |
