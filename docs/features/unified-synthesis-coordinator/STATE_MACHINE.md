# SynthesisCoordinator State Machine

## Overview

The `SynthesisCoordinator` is a unified synthesis system that replaces 5 legacy synthesis paths with a single, predictable state machine. It coordinates all TTS synthesis requests with deduplication, priority queuing, and per-engine concurrency control.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PlaybackController                               │
│                                                                         │
│  ┌─────────────┐     ┌──────────────────────────────────────────────┐  │
│  │ User Intent │     │           SynthesisCoordinator               │  │
│  │   (play)    │────>│                                              │  │
│  └─────────────┘     │  ┌─────────────────────────────────────────┐ │  │
│                      │  │          Priority Queue                  │ │  │
│                      │  │  (SplayTreeSet<SynthesisRequest>)        │ │  │
│                      │  │                                          │ │  │
│                      │  │  [immediate(3)] > [prefetch(2)] > [bg(1)]│ │  │
│                      │  └────────────────┬────────────────────────┘ │  │
│                      │                   │                          │  │
│                      │  ┌────────────────▼────────────────────────┐ │  │
│                      │  │          Worker Loop                     │ │  │
│                      │  │  (async, runs continuously)              │ │  │
│                      │  └────────────────┬────────────────────────┘ │  │
│                      │                   │                          │  │
│                      │  ┌────────────────▼────────────────────────┐ │  │
│                      │  │     Per-Engine Semaphores               │ │  │
│                      │  │  kokoro: 3, piper: 2, supertonic: 2     │ │  │
│                      │  └────────────────┬────────────────────────┘ │  │
│                      │                   │                          │  │
│                      │  ┌────────────────▼────────────────────────┐ │  │
│                      │  │         RoutingEngine                    │ │  │
│                      │  │   synthesizeToWavFile()                  │ │  │
│                      │  └────────────────┬────────────────────────┘ │  │
│                      │                   │                          │  │
│                      │  ┌────────────────▼────────────────────────┐ │  │
│                      │  │         Event Streams                    │ │  │
│                      │  │  onSegmentReady / onSegmentFailed       │ │  │
│                      │  └───────────────────────────────────────┬─┘ │  │
│                      └──────────────────────────────────────────┼───┘  │
│                                                                 │      │
│  ┌──────────────────────────────────────────────────────────────▼──┐  │
│  │                    AudioOutput                                  │  │
│  │                  playFile() / resume()                          │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## State Diagram

```
                                 ┌───────────────────┐
                                 │                   │
                    ┌────────────│     IDLE          │◄────────────────┐
                    │            │   (queue empty)   │                 │
                    │            └─────────┬─────────┘                 │
                    │                      │                           │
                    │            queueRange() called                   │
                    │                      │                           │
                    │                      ▼                           │
                    │            ┌─────────────────────┐               │
                    │            │   ENQUEUEING        │               │
                    │            │                     │               │
                    │            │ • Check cache       │               │
                    │            │ • Deduplicate       │               │
                    │            │ • Add to queue      │               │
                    │            │ • Wake worker       │               │
                    │            └─────────┬──────────┘                │
                    │                      │                           │
         reset() / │          for each segment:                       │
         dispose() │                      │                           │
                   │         ┌────────────┼────────────┐               │
                   │         │            │            │               │
                   │         ▼            ▼            ▼               │
                   │    [cached]    [duplicate]  [new request]        │
                   │         │            │            │               │
                   │         │            │            ▼               │
                   │         │            │   ┌──────────────────┐    │
                   │         │            │   │    QUEUED        │    │
                   │         │            │   │                  │    │
                   │         │            │   │ priority queue:  │    │
                   │         │            │   │ immediate > pref │    │
                   │         │            │   │  > background    │    │
                   │         │            │   └────────┬─────────┘    │
                   │         │            │            │               │
                   │         │            │   worker picks request    │
                   │         │            │            │               │
                   │         │            │            ▼               │
                   │         │            │   ┌──────────────────┐    │
                   │         │            │   │ AWAITING_SLOT    │    │
                   │         │            │   │                  │    │
                   │         │            │   │ semaphore.wait() │    │
                   │         │            │   └────────┬─────────┘    │
                   │         │            │            │               │
                   │         │            │     slot acquired         │
                   │         │            │            │               │
                   │         │            │            ▼               │
                   │         │            │   ┌──────────────────┐    │
                   │         │            │   │   IN_FLIGHT      │    │
                   │         │            │   │                  │    │
                   │         │            │   │ • In _inFlightKeys│   │
                   │         │            │   │ • synthesize()   │    │
                   │         │            │   │ • timeout: 30s   │    │
                   │         │            │   └───────┬──────────┘    │
                   │         │            │           │                │
                   │         │            │      ┌────┴────┐          │
                   │         │            │      │         │          │
                   │         ▼            ▼      ▼         ▼          │
                   │    ┌─────────────────────────┐ ┌───────────────┐ │
                   │    │      READY              │ │    FAILED     │ │
                   │    │                         │ │               │ │
                   │    │ emit onSegmentReady     │ │ emit onFailed │ │
                   │    └────────────┬────────────┘ └───────┬───────┘ │
                   │                 │                      │         │
                   │                 └──────────┬───────────┘         │
                   │                            │                     │
                   │                  release semaphore               │
                   │                            │                     │
                   │                 queue.isEmpty && inFlight.isEmpty?
                   │                            │                     │
                   │                       ┌────┴────┐                │
                   │                       │         │                │
                   │                      yes        no               │
                   │                       │         │                │
                   └───────────────────────┘         └────────────────┘
                                                      (process next)
```

## Request Lifecycle

### 1. Request Creation (`queueRange`)

```dart
// Segment goes through deduplication checks
for each segment in range:
  cacheKey = generate(voiceId, text, rate)
  
  if (cache.isReady(cacheKey)):
    emit onSegmentReady(wasFromCache: true)  // Cache hit
    continue
    
  if (_inFlightKeys.contains(key)):
    continue  // Already synthesizing
    
  if (_pendingByKey.contains(key)):
    existing.upgradePriority(newPriority)  // Priority upgrade
    continue
    
  // New request - add to queue
  queue.add(SynthesisRequest(...))
  pendingByKey[key] = request
```

### 2. Worker Processing (`_workerLoop`)

```dart
while (!disposed):
  if (queue.isEmpty):
    wait(_workerWakeup)  // Sleep until woken
    
  request = queue.removeFirst()  // Highest priority
  pendingByKey.remove(request.key)
  
  semaphore = getSemaphore(engineType)
  await semaphore.acquire()  // Wait for slot
  
  inFlightKeys.add(request.key)
  try:
    result = await engine.synthesize().timeout(30s)
    emit onSegmentReady(wasFromCache: false)
  catch:
    emit onSegmentFailed(error)
  finally:
    inFlightKeys.remove(request.key)
    semaphore.release()
```

### 3. Event Handling (PlaybackController)

```dart
// Set up listeners in constructor
_coordinatorReadySub = coordinator.onSegmentReady.listen((event) {
  if (event.segmentIndex == _waitingForSegmentIndex):
    _waitingForSegmentCompleter.complete()
});

// Wait for segment before playback
await _waitForSegmentReady(currentIndex)
await _playFromCache(currentIndex)
_queueMoreSegmentsIfNeeded()
```

## Priority System

| Priority    | Value | When Used                              | Example         |
|-------------|-------|----------------------------------------|-----------------|
| immediate   | 3     | Current segment, next segment          | Segments 0-1    |
| prefetch    | 2     | Lookahead buffer (within watermarks)   | Segments 2-5    |
| background  | 1     | Extended prefetch (battery permitting) | Segments 6-10   |

Within the same priority level, requests are processed in **FIFO** order (by `createdAt` timestamp).

## Concurrency Control

Each TTS engine has a maximum concurrency limit enforced by semaphores:

| Engine     | Max Concurrent | Reason                          |
|------------|----------------|---------------------------------|
| Kokoro     | 3              | High quality, can handle more   |
| Piper      | 2              | Balanced                        |
| Supertonic | 2              | Balanced                        |

The semaphore prevents "engine busy" errors that occurred with the legacy system.

## Deduplication Keys

Requests are deduplicated using the cache filename as a key:

```dart
deduplicationKey = CacheKeyGenerator.generate(
  voiceId: voiceId,
  text: text,
  playbackRate: effectiveRate,
).toFilename()
```

This ensures the same segment with the same parameters is never synthesized twice, even if requested from multiple code paths.

## Context Invalidation

When voice or playback rate changes, the entire queue is cleared:

```dart
void updateContext({required String voiceId, required double playbackRate}) {
  final key = '$voiceId|${playbackRate.toStringAsFixed(2)}';
  if (_contextKey != key) {
    _contextKey = key;
    _clearQueue();  // Discard all pending requests
  }
}
```

This prevents synthesizing segments with outdated parameters.

## Queue Management

### Queue Size Limit

The queue has a maximum size (default: 100) to prevent memory issues:

```dart
if (_queue.length >= _maxQueueSize) {
  _dropLowestPriority()  // Remove background request
}
```

### Reset Behavior

On chapter change or seek:

```dart
void reset() {
  _queue.clear()
  _pendingByKey.clear()
  // Note: in-flight requests continue but results may be ignored
}
```

## Statistics

The coordinator tracks metrics for debugging:

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

### Synthesis Timeout

Each synthesis has a 30-second timeout:

```dart
final result = await engine.synthesize().timeout(
  PlaybackConfig.synthesisTimeout,
  onTimeout: () => throw TimeoutException(...),
);
```

### Synthesis Failure

On failure, the coordinator:
1. Emits `onSegmentFailed` event
2. Releases the semaphore slot
3. Continues processing other requests
4. Lets the caller decide retry strategy

## Integration with PlaybackController

```
PlaybackController                          SynthesisCoordinator
      │                                              │
      │  1. loadChapter()                            │
      │─────────────────────►  reset()               │
      │                                              │
      │  2. play() → _speakCurrent()                 │
      │─────────────────────►  updateContext()       │
      │                                              │
      │  3. queue current+next at immediate          │
      │─────────────────────►  queueRange()          │
      │                                              │
      │  4. wait for segment                         │
      │◄───────────────────── onSegmentReady         │
      │                                              │
      │  5. play from cache                          │
      │─────────────────────►                        │
      │                                              │
      │  6. queue more segments                      │
      │─────────────────────►  queueRange(prefetch)  │
      │                                              │
```

## Benefits Over Legacy System

| Aspect                | Legacy (5 paths)                    | Coordinator (1 path)            |
|-----------------------|-------------------------------------|---------------------------------|
| Deduplication         | None (duplicate synthesis common)   | Automatic (by cache key)        |
| Concurrency           | Uncontrolled ("busy" errors)        | Per-engine semaphores           |
| Priority              | Implicit (code order)               | Explicit (3 levels)             |
| Queue Management      | Scattered across paths              | Single priority queue           |
| Context Changes       | Race conditions                     | Atomic clear + requeue          |
| Code Lines            | ~1,200                              | ~690                            |
| Testability           | Difficult (many paths)              | Easy (single entry point)       |
