# Configuration Flexibility Implementation Plan

## Overview

This document outlines a plan to address the configuration flexibility issues (F1-F5) identified in the architecture audit, along with related edge cases that benefit from a unified configuration system.

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

---

## Issue Analysis

### F1. Hard-coded Prefetch Window Sizes Not Adaptive

**Current State:**
- `maxPrefetchTracks = 10` (static)
- Battery-based modes exist but are limited to 3 presets

**Problem:**
- Doesn't adapt to queue length (prefetching 15 tracks for a 5-track chapter is wasteful)
- Doesn't consider measured RTF (fast devices could prefetch more)
- Network conditions not considered

**Proposed Solution:**
```dart
class AdaptivePrefetchConfig {
  /// Calculates optimal prefetch window based on runtime factors
  int calculatePrefetchWindow({
    required int queueLength,
    required double measuredRTF,
    required SynthesisMode mode,
    required bool isCharging,
  }) {
    // Base from mode
    var tracks = mode.maxPrefetchTracks;
    
    // Don't exceed queue
    tracks = min(tracks, queueLength);
    
    // If RTF is fast, can prefetch more
    if (measuredRTF < 0.5) {
      tracks = (tracks * 1.5).round();
    }
    
    // If charging, be more aggressive
    if (isCharging) {
      tracks = (tracks * 1.25).round();
    }
    
    return tracks;
  }
}
```

---

### F2. Resume Timer Not Cancellable

**Current State:**
- `prefetchResumeDelay = 500ms` fixed
- No way to resume prefetch manually

**Problem:**
- User seeks, waits 500ms, seeks again → timer resets unnecessarily
- Can't resume immediately when user finishes seeking

**Proposed Solution:**
```dart
class BufferScheduler {
  Duration _resumeDelay;
  
  /// Configurable at runtime
  void setResumeDelay(Duration delay) {
    _resumeDelay = delay;
  }
  
  /// Manual resume (bypasses timer)
  void resumeImmediately() {
    _resumeTimer?.cancel();
    _isSuspended = false;
    _onResume?.call();
  }
}
```

---

### F3. No Configuration for SmartSynthesisManager Strategy

**Current State:**
- `EngineConfig` abstract with hardcoded values
- No way to override per-instance

**Problem:**
- Can't tune synthesis strategy for specific books or devices

**Proposed Solution:**
```dart
class SmartSynthesisManager {
  SmartSynthesisManager({
    SynthesisStrategy? strategy,
  }) : _strategy = strategy ?? DefaultSynthesisStrategy();
  
  final SynthesisStrategy _strategy;
}

abstract class SynthesisStrategy {
  int get preSynthesizeCount;
  bool shouldContinuePrefetch(int bufferedMs);
}
```

---

### F4. Cache Budget Not Configurable at Runtime

**Current State:**
- `CacheBudget` defaults: 500 MB max, 7 days max age
- Can't adjust based on available storage

**Problem:**
- Device with 256 GB might want larger cache
- Device with limited storage needs smaller cache

**Proposed Solution:**
```dart
class IntelligentCacheManager {
  /// Update budget at runtime
  void updateBudget(CacheBudget newBudget) {
    _budget = newBudget;
    // Prune if new budget is smaller
    unawaited(pruneIfNeeded());
  }
  
  /// Auto-configure based on available storage
  Future<void> autoConfigure() async {
    final available = await getAvailableStorage();
    final suggested = CacheBudget(
      // Use up to 10% of free space, max 2 GB
      maxSizeBytes: min(available ~/ 10, 2 * 1024 * 1024 * 1024),
    );
    updateBudget(suggested);
  }
}
```

---

### F5. Prefetch Concurrency Ignored

**Current State:**
- `prefetchConcurrency = 1` (unused)
- `DeviceEngineConfig.prefetchConcurrency` exists but not connected
- `SynthesisModeConfig.concurrencyLimit` exists but not used

**Problem:**
- Three separate sources of truth for concurrency
- None are actually used in prefetch loops

**Proposed Solution:**
1. Remove unused `PlaybackConfig.prefetchConcurrency`
2. Use `DeviceEngineConfig.prefetchConcurrency` as the source of truth
3. Pass to scheduler for parallel synthesis (when implemented)

```dart
class BufferScheduler {
  int _concurrency = 1;
  
  void setConcurrency(int concurrency) {
    _concurrency = concurrency.clamp(1, 4);
  }
  
  Future<void> runPrefetch(...) async {
    if (_concurrency == 1) {
      // Current sequential implementation
    } else {
      // Use Semaphore for parallel synthesis
      final semaphore = Semaphore(_concurrency);
      await Future.wait(segments.map((s) async {
        await semaphore.acquire();
        try {
          await synthesize(s);
        } finally {
          semaphore.release();
        }
      }));
    }
  }
}
```

---

## Related Issues to Include

### E2. Voice Change Mid-Prefetch

**Connection to F1/F3:** When voice changes, prefetch window and strategy need recalculation.

**Proposed Solution:**
- Add `onVoiceChanged` hook to PlaybackController
- Clear cache entries with old voice prefix
- Reset scheduler with new context

### E3. Out-of-Memory During Prefetch

**Connection to F1/F4:** OOM indicates prefetch is too aggressive or cache too large.

**Proposed Solution:**
- Catch `OutOfMemoryError` in synthesis
- Auto-reduce prefetch window temporarily
- Trigger immediate cache pruning
- Report to metrics (Q11)

### E5. Rapid Rate Changes

**Connection to F3/F4:** Rate changes invalidate cached audio.

**Proposed Solution:**
- If `rateIndependentSynthesis = true` (current default), cache is still valid
- If false, clear cache entries with old rate
- Update F3 strategy to consider rate changes

---

## Implementation Plan

### Phase 1: Foundation (1 sprint)

| Task | Effort | Priority |
|------|--------|----------|
| Create `RuntimePlaybackConfig` class | Medium | High |
| Add `updateBudget()` to CacheManager | Low | High |
| Remove unused `prefetchConcurrency` | Low | Medium |

**Deliverable:** Runtime-configurable cache budget

### Phase 2: Adaptive Prefetch (1-2 sprints)

| Task | Effort | Priority |
|------|--------|----------|
| Implement `AdaptivePrefetchConfig` | Medium | High |
| Add resume delay configurability | Low | Medium |
| Add `resumeImmediately()` to scheduler | Low | Low |

**Deliverable:** Prefetch window adapts to queue/device

### Phase 3: Parallel Synthesis (2 sprints)

| Task | Effort | Priority |
|------|--------|----------|
| Implement Semaphore-based parallel synthesis | High | Medium |
| Wire `DeviceEngineConfig.prefetchConcurrency` | Medium | Medium |
| Add concurrency to settings UI | Low | Low |

**Deliverable:** Optional parallel synthesis on capable devices

### Phase 4: User Settings (1 sprint)

| Task | Effort | Priority |
|------|--------|----------|
| Add settings screen for cache size | Low | Medium |
| Add advanced prefetch settings | Medium | Low |
| Add synthesis timeout setting | Low | Low |

**Deliverable:** Power user controls

---

## Settings UI Design

### Cache Settings
```
Cache Size: [Auto / 500 MB / 1 GB / 2 GB / 4 GB]
Max Age: [7 days / 14 days / 30 days / Never expire]
[Clear Cache] [Auto-tune for this device]
```

### Prefetch Settings (Advanced)
```
Prefetch Mode: [Adaptive / Aggressive / Conservative / Off]
Parallel Synthesis: [Auto / 1 / 2 / 4] threads
Resume Delay: [250ms / 500ms / 1s]
```

---

## Success Metrics

1. **Cache utilization**: Target 60-80% of configured budget used
2. **Buffer underruns**: < 1% of playback sessions
3. **Battery impact**: No increase vs current implementation
4. **User satisfaction**: Settings discoverable but not overwhelming

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Complexity increase | Default to current behavior; advanced settings hidden |
| Parallel synthesis bugs | Gate behind feature flag; extensive testing |
| User confusion | Clear explanations; "Auto" as default |
| Device-specific issues | Comprehensive device profiling |

---

## Open Questions

1. Should we expose RTF measurements to users?
2. How granular should cache control be (per-book vs global)?
3. Should we auto-adjust settings based on error rates?

---

## References

- [improvement_opportunities.md](../../architecture/improvement_opportunities.md) - F1-F5, E2-E5
- [AUTO_TUNING_SYSTEM.md](../smart-audio-synth/AUTO_TUNING_SYSTEM.md) - Device profiling design
- [engine_config.dart](../../../packages/playback/lib/src/engine_config.dart) - DeviceEngineConfig
