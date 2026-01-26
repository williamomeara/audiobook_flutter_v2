# SynthesisCoordinator State Machine

## Overview

The `SynthesisCoordinator` is a unified synthesis system that replaces 5 legacy synthesis paths with a single, predictable state machine. It coordinates all TTS synthesis requests with deduplication, priority queuing, and per-engine concurrency control.

## Key Components

### Core Classes

- **SynthesisCoordinator**: Main coordinator with worker loop, event streams, and queue management
- **SynthesisRequest**: Individual request with priority, cache key, and deduplication key
- **SynthesisPriority**: Three-level priority enum (immediate, prefetch, background)
- **Semaphore**: Per-engine concurrency control

### Event Streams

| Stream | Payload | When Emitted |
|--------|---------|--------------|
| `onSegmentReady` | `SegmentReadyEvent` | Segment in cache (hit or newly synthesized) |
| `onSegmentFailed` | `SegmentFailedEvent` | Synthesis error or timeout |
| `onQueueEmpty` | `void` | Queue empty AND no in-flight requests |

## Architecture

```
+-------------------------------------------------------------------------+
|                        PlaybackController                               |
|                                                                         |
|  +-------------+     +----------------------------------------------+  |
|  | User Intent |     |           SynthesisCoordinator               |  |
|  |   (play)    |---->|                                              |  |
|  +-------------+     |  +------------------------------------------+ |  |
|                      |  |          Priority Queue                  | |  |
|                      |  |  (SplayTreeSet<SynthesisRequest>)        | |  |
|                      |  |                                          | |  |
|                      |  |  [immediate(3)] > [prefetch(2)] > [bg(1)]| |  |
|                      |  +------------------+-----------------------+ |  |
|                      |                     |                         |  |
|                      |  +------------------v-----------------------+ |  |
|                      |  |          Worker Loop                     | |  |
|                      |  |  (async, runs continuously)              | |  |
|                      |  +------------------+-----------------------+ |  |
|                      |                     |                         |  |
|                      |  +------------------v-----------------------+ |  |
|                      |  |     Per-Engine Semaphores               | |  |
|                      |  |  kokoro: 3, piper: 2, supertonic: 2     | |  |
|                      |  +------------------+-----------------------+ |  |
|                      |                     |                         |  |
|                      |  +------------------v-----------------------+ |  |
|                      |  |         RoutingEngine                    | |  |
|                      |  |   synthesizeToWavFile()                  | |  |
|                      |  +------------------+-----------------------+ |  |
|                      |                     |                         |  |
|                      |  +------------------v-----------------------+ |  |
|                      |  |         Event Streams                    | |  |
|                      |  |  onSegmentReady / onSegmentFailed       | |  |
|                      |  +------------------+----------------------++ |  |
|                      +----------------------|----------------------+    |
|                                             |                          |
|  +------------------------------------------v-----------------------+  |
|  |                    AudioOutput                                   |  |
|  |                  playFile() / resume()                           |  |
|  +------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

## State Diagram

```
                                 +-------------------+
                                 |                   |
                    +------------|      IDLE         |<----------------+
                    |            |   (queue empty)   |                 |
                    |            +---------+---------+                 |
                    |                      |                           |
                    |            queueRange() called                   |
                    |                      |                           |
                    |                      v                           |
                    |            +---------------------+               |
                    |            |   ENQUEUEING        |               |
                    |            |                     |               |
                    |            | * Check cache       |               |
                    |            | * Deduplicate       |               |
                    |            | * Add to queue      |               |
                    |            | * Wake worker       |               |
                    |            +---------+----------+                |
                    |                      |                           |
         reset() / |          for each segment:                       |
         dispose() |                      |                           |
                   |         +------------+------------+               |
                   |         |            |            |               |
                   |         v            v            v               |
                   |    [cached]    [duplicate]  [new request]        |
                   |         |            |            |               |
                   |    emit |   upgrade  |            v               |
                   |    Ready|   priority |   +------------------+    |
                   |         |            |   |    QUEUED        |    |
                   |         |            |   |                  |    |
                   |         |            |   | priority queue:  |    |
                   |         |            |   | immediate > pref |    |
                   |         |            |   |  > background    |    |
                   |         |            |   +--------+---------+    |
                   |         |            |            |               |
                   |         |            |   worker picks request    |
                   |         |            |   (highest priority first) |
                   |         |            |            |               |
                   |         |            |            v               |
                   |         |            |   +------------------+    |
                   |         |            |   | AWAITING_SLOT    |    |
                   |         |            |   |                  |    |
                   |         |            |   | semaphore.wait() |    |
                   |         |            |   | (per-engine)     |    |
                   |         |            |   +--------+---------+    |
                   |         |            |            |               |
                   |         |            |     slot acquired         |
                   |         |            |            |               |
                   |         |            |            v               |
                   |         |            |   +------------------+    |
                   |         |            |   |   IN_FLIGHT      |    |
                   |         |            |   |                  |    |
                   |         |            |   | * Double-check   |    |
                   |         |            |   |   cache (race)   |    |
                   |         |            |   | * synthesize()   |    |
                   |         |            |   | * timeout: 30s   |    |
                   |         |            |   +-------+----------+    |
                   |         |            |           |                |
                   |         |            |      +----+----+          |
                   |         |            |      |         |          |
                   |         v            v      v         v          |
                   |    +-------------------------+ +---------------+ |
                   |    |      READY              | |    FAILED     | |
                   |    |                         | |               | |
                   |    | emit onSegmentReady     | | emit onFailed | |
                   |    | (wasFromCache: T/F)     | | (+ error info)| |
                   |    +------------+------------+ +-------+-------+ |
                   |                 |                      |         |
                   |                 +----------+-----------+         |
                   |                            |                     |
                   |                  release semaphore               |
                   |                  remove from inFlightKeys        |
                   |                            |                     |
                   |                 queue.isEmpty && inFlight.isEmpty?
                   |                            |                     |
                   |                       +----+----+                |
                   |                       |         |                |
                   |                      yes        no               |
                   |                       |         |                |
                   |             emit onQueueEmpty   +----------------+
                   |                       |          (process next)
                   +-----------------------+
```

## Request Lifecycle

### 1. Request Creation (`queueRange`)

```dart
Future<void> queueRange({
  required List<AudioTrack> tracks,
  required String voiceId,
  required double playbackRate,
  required int startIndex,
  required int endIndex,
  SynthesisPriority priority = SynthesisPriority.prefetch,
}) async {
  // For each segment in range:
  for (var i = startIndex; i <= endIndex; i++) {
    final cacheKey = CacheKeyGenerator.generate(...);
    final dedupeKey = cacheKey.toFilename();
    
    // Path 1: Already in cache -> emit Ready immediately
    if (await cache.isReady(cacheKey)) {
      _emitReady(segmentIndex: i, wasFromCache: true);
      continue;
    }
    
    // Path 2: Already in-flight -> skip (synthesis in progress)
    if (_inFlightKeys.contains(dedupeKey)) {
      continue;
    }
    
    // Path 3: Already queued -> upgrade priority if higher
    if (_pendingByKey.containsKey(dedupeKey)) {
      _pendingByKey[dedupeKey]!.upgradePriority(priority);
      continue;
    }
    
    // Path 4: New request -> add to priority queue
    _queue.add(SynthesisRequest(...));
    _pendingByKey[dedupeKey] = request;
  }
  
  _wakeWorker();  // Wake worker if items added
}
```

### 2. Worker Processing (`_workerLoop`)

```dart
Future<void> _workerLoop() async {
  while (!_disposed) {
    // Sleep if queue empty
    if (_queue.isEmpty) {
      _workerWakeup = Completer<void>();
      await _workerWakeup!.future;
    }
    
    // Get highest priority request
    final request = _queue.first;
    _queue.remove(request);
    _pendingByKey.remove(request.deduplicationKey);
    
    // Process asynchronously (allows concurrent synthesis)
    unawaited(_processRequest(request));
  }
}
```

### 3. Request Processing (`_processRequest`)

```dart
Future<void> _processRequest(SynthesisRequest request) async {
  final semaphore = _getSemaphore(engineType);
  
  // 1. Wait for concurrency slot
  await semaphore.acquire();
  
  // 2. Mark as in-flight
  _inFlightKeys.add(request.deduplicationKey);
  
  try {
    // 3. Double-check cache (another path might have won race)
    if (await cache.isReady(request.cacheKey)) {
      _emitReady(wasFromCache: true);
      return;
    }
    
    // 4. Synthesize with timeout
    final result = await engine.synthesizeToWavFile(...)
        .timeout(PlaybackConfig.synthesisTimeout);  // 30s default
    
    // 5. Emit success
    _emitReady(durationMs: result.durationMs, wasFromCache: false);
    
  } on TimeoutException catch (e) {
    _emitFailed(error: e, isTimeout: true);
  } catch (e) {
    _emitFailed(error: e, isTimeout: false);
  } finally {
    // 6. Cleanup
    _inFlightKeys.remove(request.deduplicationKey);
    semaphore.release();
    
    // 7. Check if all work done
    if (_queue.isEmpty && _inFlightKeys.isEmpty) {
      _queueEmptyController.add(null);
    }
  }
}
```

### 4. Event Handling (PlaybackController)

```dart
// Set up listeners in constructor
_coordinatorReadySub = coordinator.onSegmentReady.listen((event) {
  if (event.segmentIndex == _waitingForSegmentIndex) {
    _waitingForSegmentCompleter?.complete();
  }
});

// Wait for segment before playback
await _waitForSegmentReady(currentIndex);
await _playFromCache(currentIndex);
_queueMoreSegmentsIfNeeded();
```

## Priority System

| Priority    | Value | When Used                              | Typical Segments |
|-------------|-------|----------------------------------------|------------------|
| immediate   | 3     | Current + next segment (playback)      | 0-1              |
| prefetch    | 2     | Lookahead buffer (within watermarks)   | 2-5              |
| background  | 1     | Extended prefetch (battery permitting) | 6+               |

**Priority Upgrade**: If a segment already queued at `prefetch` is re-requested at `immediate`, its priority is upgraded without creating a duplicate.

**FIFO Within Priority**: Requests at the same priority level are processed in creation order (via `createdAt` timestamp).

## Concurrency Control

Per-engine semaphores prevent "busy" errors:

| Engine     | Max Concurrent | Reason                            |
|------------|----------------|-----------------------------------|
| Kokoro     | 3              | High quality, can handle more     |
| Piper      | 2              | Balanced resource usage           |
| Supertonic | 2              | Balanced resource usage           |

```dart
Semaphore _getSemaphore(String engineType) {
  return _engineSemaphores.putIfAbsent(
    engineType,
    () => Semaphore(PlaybackConfig.getConcurrencyForEngine(engineType)),
  );
}
```

## Deduplication

Requests are deduplicated using the cache key filename:

```dart
deduplicationKey = CacheKeyGenerator.generate(
  voiceId: voiceId,
  text: text,
  playbackRate: effectiveRate,
).toFilename();
```

**Three-layer deduplication**:
1. **Queue dedup**: `_pendingByKey` map prevents duplicate queue entries
2. **In-flight dedup**: `_inFlightKeys` set skips segments being synthesized
3. **Cache dedup**: Double-check before synthesis catches race conditions

## Context Invalidation

When voice or playback rate changes, all pending work is invalidated:

```dart
bool updateContext({required String voiceId, required double playbackRate}) {
  final key = '$voiceId|${playbackRate.toStringAsFixed(2)}';
  if (_contextKey != key) {
    _contextKey = key;
    _clearQueue();  // Discard all pending requests
    return true;
  }
  return false;
}
```

**Note**: In-flight requests continue (can't cancel native TTS), but their results won't cause issues since cache keys don't match new context.

## Queue Management

### Maximum Size

```dart
final int _maxQueueSize = 100;  // Prevents memory issues

if (_queue.length >= _maxQueueSize) {
  _dropLowestPriority();  // Remove background request first
}
```

### Reset Behavior

Called on chapter change, seek, or voice change:

```dart
void reset() {
  _queue.clear();
  _pendingByKey.clear();
  // In-flight requests continue but results may be discarded
  _wakeWorker();
}
```

## Statistics

For debugging and monitoring:

```dart
Map<String, int> get stats => {
  'queued': _totalQueued,
  'completed': _totalCompleted,
  'failed': _totalFailed,
  'cacheHits': _cacheHits,
  'currentQueue': _queue.length,
  'inFlight': _inFlightKeys.length,
};
```

## Error Handling

### Timeout (30s default)

```dart
final result = await engine.synthesize().timeout(
  PlaybackConfig.synthesisTimeout,
  onTimeout: () => throw TimeoutException('Synthesis timed out'),
);
```

### Failure Recovery

On failure:
1. Emit `onSegmentFailed` with error details and `isTimeout` flag
2. Release semaphore slot
3. Continue processing other requests
4. Caller decides retry strategy (PlaybackController may retry or skip)

## PlaybackController Integration

```
PlaybackController                          SynthesisCoordinator
      |                                              |
      |  1. loadChapter()                            |
      |--------------------->  reset()               |
      |                                              |
      |  2. play() -> _speakCurrent()                |
      |--------------------->  updateContext()       |
      |                                              |
      |  3. queue current+next at immediate          |
      |--------------------->  queueRange()          |
      |                                              |
      |  4. wait for segment                         |
      |<--------------------- onSegmentReady         |
      |                                              |
      |  5. play from cache                          |
      |--------------------->                        |
      |                                              |
      |  6. queue more segments (prefetch)           |
      |--------------------->  queueRange()          |
      |                                              |
      |  7. onComplete: advance index                |
      |<---------------------                        |
      |                                              |
      |  8. repeat from step 3                       |
      |                                              |
```

## Benefits Over Legacy System

| Aspect                | Legacy (5 paths)                    | Coordinator (1 path)            |
|-----------------------|-------------------------------------|---------------------------------|
| Deduplication         | None (duplicate synthesis common)   | Automatic (3-layer)             |
| Concurrency           | Uncontrolled ("busy" errors)        | Per-engine semaphores           |
| Priority              | Implicit (code order)               | Explicit (3 levels + upgrade)   |
| Queue Management      | Scattered across paths              | Single priority queue           |
| Context Changes       | Race conditions                     | Atomic clear + requeue          |
| Code Lines            | ~1,200                              | ~600                            |
| Testability           | Difficult (many paths)              | Easy (single entry point)       |
| Visibility            | Hidden state in multiple places     | Clear stats + event streams     |
