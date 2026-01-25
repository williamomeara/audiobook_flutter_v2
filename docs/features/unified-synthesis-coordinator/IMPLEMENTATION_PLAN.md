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

### Step 3: Enable and Test (NEXT)
- [ ] Set `useUnifiedSynthesis = true` in PlaybackConfig
- [ ] Test on device with real audiobook
- [ ] Monitor logs for issues
- [ ] Compare battery usage

### Step 4: Remove legacy code (AFTER TESTING)
- [ ] Delete old synthesis paths (see Phase 3 above)
- [ ] Remove feature flag
- [ ] Update documentation

---

## Files Created ✅

- [x] `packages/playback/lib/src/synthesis/synthesis_coordinator.dart`
- [x] `packages/playback/lib/src/synthesis/synthesis_request.dart`
- [x] `packages/playback/test/synthesis_coordinator_test.dart`

## Files Modified ✅

- [x] `packages/playback/lib/src/playback_controller.dart` (added coordinator integration)
- [x] `packages/playback/lib/src/playback_config.dart` (added feature flag)
- [x] `packages/playback/lib/src/synthesis/synthesis.dart` (export new files)

## Files to Delete (Phase 3, after testing)

Legacy code to remove once unified synthesis is tested and stable:

| Location | Component | Estimated Lines |
|----------|-----------|-----------------|
| `playback_controller.dart` | `_startImmediatePrefetch()` | ~20 |
| `playback_controller.dart` | `_runImmediatePrefetch()` | ~70 |
| `playback_controller.dart` | `_startImmediateNextPrefetch()` | ~25 |
| `playback_controller.dart` | `_startPrefetchIfNeeded()` | ~45 |
| `playback_controller.dart` | Legacy `_speakCurrent()` synthesis code | ~90 |
| `buffer_scheduler.dart` | `runParallelPrefetch()` | ~115 |
| `buffer_scheduler.dart` | `prefetchNextSegmentImmediately()` | ~100 |
| `buffer_scheduler.dart` | `runPrefetch()` | ~115 |
| `parallel_orchestrator.dart` | Entire file | ~435 |
| `tts_engines` | `SmartSynthesisManager` | ~200 |

**Total estimated removal: ~1,215 lines**

---

## Success Criteria

- [ ] Single synthesis path for all segments
- [ ] No "busy" errors under normal operation
- [ ] No duplicate synthesis requests (verified via logs)
- [ ] Playback works correctly on chapter load, seek, and track advance
- [ ] Battery usage reduced (measure before/after)
- [ ] Code reduction: ~900+ lines removed
- [ ] All existing tests pass or updated

---

## Risks

1. **Regressions** - Careful testing needed before removing old code
2. **Edge cases** - Rapid seeking, chapter changes, voice switches
3. **Memory** - Queue could grow large if synthesis is slow; need max size

## Timeline Estimate

- Phase 1: 2-3 hours (create coordinator) ✅ Done
- Phase 2: 2-3 hours (integrate) ✅ Done
- Phase 3: 1-2 hours (remove code) - After testing
- Phase 4: 1 hour (cleanup) - After testing
- Testing: 2-3 hours

**Total: ~10-12 hours**
