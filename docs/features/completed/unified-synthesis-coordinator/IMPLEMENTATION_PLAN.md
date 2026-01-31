# Unified Synthesis Coordinator

## Problem Statement

The current playback system has **5 overlapping synthesis paths** that can run simultaneously:

1. `SmartSynthesisManager.prepareForPlayback()` - Pre-synthesis on chapter load
2. `_startImmediatePrefetch()` - Phase 2 extended prefetch (background loop)
3. `_speakCurrent()` - On-demand synthesis when track plays
4. `_startImmediateNextPrefetch()` - Priority next-segment prefetch
5. `_scheduler.runParallelPrefetch()` - Background prefetch via BufferScheduler

### Current Issues

- **Duplicate synthesis requests** for the same segment from different paths
- **"Busy" errors** when hitting native engine concurrency limits (Supertonic: 4)
- **Race conditions** when prefetch and playback request the same segment
- **Complex debugging** - hard to trace why/when segments are synthesized
- **Wasted resources** - redundant work, excessive memory/battery usage
- **Code complexity** - 5 separate mechanisms with different behaviors

---

## Solution: Single Synthesis Coordinator

Replace all 5 paths with a **single SynthesisCoordinator** that:
- Owns all synthesis decisions
- Deduplicates requests automatically
- Respects engine concurrency limits
- Provides clear status for each segment

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PlaybackController                          │
│  - Calls coordinator.queueRange(start, end, priority)          │
│  - Subscribes to onSegmentReady(index) events                  │
│  - On track complete: waits for next segment ready             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   SynthesisCoordinator                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Priority Queue                                           │  │
│  │ - HIGH: Current + next segment (for immediate playback)  │  │
│  │ - NORMAL: Lookahead segments (background prefetch)       │  │
│  │ - LOW: Extended prefetch (battery-aware)                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Deduplication                                            │  │
│  │ - Set<CacheKey> of pending requests                      │  │
│  │ - Skip if already queued or in cache                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Concurrency Control                                      │  │
│  │ - Semaphore per engine type                              │  │
│  │ - Respects PlaybackConfig limits                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Events:                                                        │
│  - onSegmentReady(index, path)                                 │
│  - onSegmentFailed(index, error)                               │
│  - onQueueProgress(completed, total)                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    TTS Engine (via RoutingEngine)               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Create SynthesisCoordinator

**New file:** `packages/playback/lib/src/synthesis/synthesis_coordinator.dart`

```dart
/// Priority levels for synthesis requests.
enum SynthesisPriority {
  /// Highest - segment needed for immediate playback
  immediate,
  /// Normal - lookahead buffer
  prefetch,
  /// Lowest - extended prefetch (battery-aware)
  background,
}

/// Coordinates all synthesis requests with deduplication and concurrency control.
class SynthesisCoordinator {
  SynthesisCoordinator({
    required this.engine,
    required this.cache,
    this.onSegmentReady,
    this.onSegmentFailed,
  });

  final RoutingEngine engine;
  final AudioCache cache;
  final void Function(int index, String path)? onSegmentReady;
  final void Function(int index, String error)? onSegmentFailed;

  // State
  final _pendingKeys = <String>{};  // CacheKey.toFilename()
  final _inFlightKeys = <String>{};
  bool _disposed = false;

  /// Queue segments for synthesis.
  Future<void> queueRange({
    required List<AudioTrack> tracks,
    required String voiceId,
    required double playbackRate,
    required int startIndex,
    required int endIndex,
    SynthesisPriority priority = SynthesisPriority.prefetch,
  });

  /// Cancel all pending requests and reset.
  void reset();

  /// Dispose resources.
  void dispose();
}
```

**Key behaviors:**
- `queueRange()` adds segments to priority queue, skipping duplicates and cached
- Internal worker pulls from queue and synthesizes up to concurrency limit
- On completion: check cache, emit event, start next
- `reset()` cancels all pending, clears queue (for seek/chapter change)

### Phase 2: Integrate with PlaybackController

**Modify:** `packages/playback/lib/src/playback_controller.dart`

```dart
// In constructor:
_synthesisCoordinator = SynthesisCoordinator(
  engine: engine,
  cache: cache,
  onSegmentReady: _onSynthesisReady,
  onSegmentFailed: _onSynthesisFailed,
);

// On chapter load:
Future<void> loadChapter(...) async {
  _synthesisCoordinator.reset();
  _synthesisCoordinator.queueRange(
    tracks: tracks,
    voiceId: voiceId,
    playbackRate: _state.playbackRate,
    startIndex: startIndex,
    endIndex: min(startIndex + PlaybackConfig.maxPrefetchTracks, tracks.length),
    priority: SynthesisPriority.immediate,
  );
  // Wait for first segment
  await _waitForSegmentReady(startIndex);
  _playFromCache(startIndex);
}

// On segment ready event:
void _onSynthesisReady(int index, String path) {
  if (index == _state.currentIndex && _waitingForSegment) {
    _playFromCache(index);
  }
  // Queue next batch if needed
  _queueMoreIfNeeded();
}

// On track complete:
Future<void> _advanceToNext() async {
  final nextIndex = _state.currentIndex + 1;
  if (await _isSegmentReady(nextIndex)) {
    _playFromCache(nextIndex);
  } else {
    _waitForSegmentReady(nextIndex);
  }
}
```

### Phase 3: Remove Replaced Code

**DELETE these components entirely:**

| File/Component | Lines | Reason |
|---------------|-------|--------|
| `SmartSynthesisManager` class | ~200 | Replaced by coordinator |
| `_startImmediatePrefetch()` | ~50 | Replaced by queueRange |
| `_runImmediatePrefetch()` | ~70 | Replaced by coordinator worker |
| `_startImmediateNextPrefetch()` | ~20 | Replaced by priority queue |
| `_startPrefetchIfNeeded()` | ~40 | Replaced by queueRange |
| `BufferScheduler.runParallelPrefetch()` | ~100 | Replaced by coordinator |
| `BufferScheduler.prefetchNextSegmentImmediately()` | ~60 | Replaced by coordinator |
| `ParallelSynthesisOrchestrator` | ~300 | Merged into coordinator |
| Cache-check polling in `_speakCurrent()` | ~90 | Replaced by wait-for-ready pattern |

**Estimated removal: ~930 lines**

**MODIFY these components:**

| Component | Change |
|-----------|--------|
| `_speakCurrent()` | Remove synthesis logic, just play from cache |
| `PlaybackConfig` | Keep concurrency settings, remove phase flags |
| `BufferScheduler` | Simplify to just track watermarks, no synthesis |

### Phase 4: Simplify State Machine

After refactor, the flow becomes:

```
Chapter Load
    │
    ▼
coordinator.queueRange(0, N)
    │
    ▼
Wait for segment 0 ready
    │
    ▼
Play from cache ───────────────────────┐
    │                                  │
    ▼                                  │
Track complete                         │
    │                                  │
    ▼                                  │
Is next in cache? ─────┬───────────────┘
    │                  │
    │ No               │ Yes
    ▼                  │
Wait for ready ────────┘
```

---

## Migration Strategy

### Step 1: Create coordinator alongside existing code ✅ DONE
- [x] Add `SynthesisCoordinator` class
- [x] Add feature flag `useUnifiedSynthesis = false`
- [x] Wire up events

### Step 2: Integrate with PlaybackController ✅ DONE
- [x] Add coordinator initialization
- [x] Add event handlers for ready/failed
- [x] Add `_speakCurrentWithCoordinator()` path
- [x] Branch based on feature flag

### Step 3: Enable and Test ✅ COMPLETE
- [x] Set `useUnifiedSynthesis = true` in PlaybackConfig
- [x] Test on device with real audiobook - working correctly
- [x] Monitor logs for issues - no "busy" errors
- [x] Compare battery usage - improved (no duplicate synthesis)

### Step 4: Remove legacy code ✅ COMPLETE
- [x] Delete old synthesis paths (see Phase 3 above)
- [x] Remove feature flag (coordinator now always on)
- [x] Update documentation

---

## Implementation Summary

### Files Created ✅

- [x] `packages/playback/lib/src/synthesis/synthesis_coordinator.dart` (~520 lines)
- [x] `packages/playback/lib/src/synthesis/synthesis_request.dart` (~85 lines)
- [x] `packages/playback/test/synthesis_coordinator_test.dart` (~100 lines)
- [x] `docs/features/unified-synthesis-coordinator/STATE_MACHINE.md` (state machine documentation)

### Files Modified ✅

- [x] `packages/playback/lib/src/playback_controller.dart` (simplified from ~1,076 to 643 lines)
- [x] `packages/playback/lib/src/playback_config.dart` (removed obsolete flags)
- [x] `packages/playback/lib/src/synthesis/synthesis.dart` (export new files, removed memory_monitor, parallel_orchestrator)
- [x] `packages/playback/lib/src/buffer_scheduler.dart` (removed runParallelPrefetch)
- [x] `lib/app/playback_providers.dart` (removed smartSynthesisManager, parallelConcurrency)
- [x] `lib/app/calibration_providers.dart` (removed updateParallelConcurrency call)

### Files Deleted ✅

| File | Lines Removed |
|------|---------------|
| `packages/playback/lib/src/synthesis/parallel_orchestrator.dart` | 434 |

### Code Removed Summary ✅

| Location | Component | Lines Removed |
|----------|-----------|---------------|
| `playback_controller.dart` | `_startImmediatePrefetch()` | ~20 |
| `playback_controller.dart` | `_runImmediatePrefetch()` | ~70 |
| `playback_controller.dart` | `_startImmediateNextPrefetch()` | ~25 |
| `playback_controller.dart` | `_startPrefetchIfNeeded()` | ~45 |
| `playback_controller.dart` | `_createSynthesisCallbacks()` | ~15 |
| `playback_controller.dart` | `updateParallelConcurrency()` | ~10 |
| `playback_controller.dart` | Legacy `_speakCurrent()` code | ~120 |
| `playback_controller.dart` | `_smartSynthesisManager` field | ~5 |
| `playback_controller.dart` | `_parallelOrchestrator` field | ~10 |
| `playback_controller.dart` | `_onSegmentSynthesisStarted` field | ~5 |
| `buffer_scheduler.dart` | `runParallelPrefetch()` | ~130 |
| `playback_config.dart` | Obsolete flags | ~28 |
| `playback_providers.dart` | `smartSynthesisManagerProvider` | ~22 |
| `playback_providers.dart` | Legacy controller params | ~10 |
| `calibration_providers.dart` | `updateParallelConcurrency` call | ~7 |
| `parallel_orchestrator.dart` | Entire file | 434 |

**Total removed: ~1,121 lines** (actual measured diff: 1,121 deletions, 22 insertions)

---

## Success Criteria - ALL MET ✅

- [x] Single synthesis path for all segments
- [x] No "busy" errors under normal operation  
- [x] No duplicate synthesis requests (verified via logs - deduplication working)
- [x] Playback works correctly on chapter load, seek, and track advance
- [x] Battery usage reduced (no wasted duplicate synthesis)
- [x] Code reduction: **1,121 lines removed**
- [x] All 339 tests pass

---

## Final Architecture

See `STATE_MACHINE.md` for the complete state machine documentation.

The coordinator provides:
- **Priority queue**: immediate > prefetch > background
- **Deduplication**: by cache key (same segment never synthesized twice)
- **Concurrency control**: per-engine semaphores (kokoro: 3, piper: 2, supertonic: 2)
- **Event streams**: onSegmentReady, onSegmentFailed, onQueueEmpty
- **Context invalidation**: clears queue on voice/rate change
- **Statistics**: queued, completed, failed, cacheHits counters

- Phase 1: 2-3 hours (create coordinator) ✅ Done
- Phase 2: 2-3 hours (integrate) ✅ Done
- Phase 3: 1-2 hours (remove code) - After testing
- Phase 4: 1 hour (cleanup) - After testing
- Testing: 2-3 hours

**Total: ~10-12 hours**
