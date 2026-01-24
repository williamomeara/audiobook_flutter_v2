# Audio Synthesis Pipeline State Machine

This document describes the synthesis pipeline that transforms text segments into playable audio files. It covers the prefetch system, cache management, concurrent synthesis, and engine coordination.

## Overview

The synthesis pipeline is responsible for:
1. Converting text segments to audio files via TTS engines
2. Caching synthesized audio for instant replay
3. Prefetching upcoming segments to eliminate playback gaps
4. Managing memory across multiple TTS engines

---

## Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SYNTHESIS PIPELINE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │  SEGMENT    │───▶│  CACHE      │───▶│  ENGINE     │───▶│  AUDIO      │  │
│  │  REQUEST    │    │  LOOKUP     │    │  SYNTHESIS  │    │  READY      │  │
│  └─────────────┘    └──────┬──────┘    └─────────────┘    └─────────────┘  │
│                            │                                                 │
│                            │ HIT                                             │
│                            ▼                                                 │
│                     ┌─────────────┐                                          │
│                     │  INSTANT    │                                          │
│                     │  RETURN     │                                          │
│                     └─────────────┘                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Segment Synthesis States

Each segment goes through the following states:

```
┌───────────────────────────────────────────────────────────────────────┐
│                    SEGMENT SYNTHESIS LIFECYCLE                        │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   ┌───────────┐                                                       │
│   │NOT_QUEUED │ ─── (not in prefetch range yet)                      │
│   └─────┬─────┘                                                       │
│         │ segment enters prefetch window                              │
│         ▼                                                             │
│   ┌───────────┐                                                       │
│   │  QUEUED   │ ─── (in queue, awaiting synthesis)                   │
│   └─────┬─────┘                                                       │
│         │ synthesis starts                                            │
│         ▼                                                             │
│   ┌───────────┐                                                       │
│   │SYNTHESIZING│ ─── (TTS engine processing)                         │
│   └─────┬─────┘                                                       │
│         │ success                    │ failure                        │
│         ▼                            ▼                                │
│   ┌───────────┐              ┌───────────┐                           │
│   │   READY   │              │  FAILED   │                           │
│   └───────────┘              └─────┬─────┘                           │
│                                    │ retry allowed                   │
│                                    ▼                                 │
│                              ┌───────────┐                           │
│                              │  QUEUED   │ (re-queued for retry)     │
│                              └───────────┘                           │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### State Definitions

| State | Description | Trigger |
|-------|-------------|---------|
| `NOT_QUEUED` | Segment not yet in prefetch range | Beyond prefetch window |
| `QUEUED` | Waiting for synthesis slot | Entered prefetch window |
| `SYNTHESIZING` | TTS engine processing | Synthesis started |
| `READY` | Audio file cached and ready | Synthesis complete |
| `FAILED` | Synthesis error occurred | Engine error, timeout |

---

## Prefetch System

### Prefetch Strategies

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         PREFETCH TIMING                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  PHASE 1: PRE-SYNTHESIS (Before Playback)                                 │
│  ═══════════════════════════════════════                                  │
│                                                                            │
│  loadChapter() ──▶ SmartSynthesisManager.prepareForPlayback()            │
│                    │                                                       │
│                    ├─ Synthesize segment[0] (BLOCKING)                    │
│                    └─ Synthesize segment[1] (background)                  │
│                                                                            │
│  PHASE 2: IMMEDIATE NEXT (During Playback)                                │
│  ═════════════════════════════════════════                                │
│                                                                            │
│  playFile(n) ──▶ prefetchNextSegmentImmediately()                        │
│                  │                                                         │
│                  └─ Target: currentIndex + 1 ONLY                         │
│                     Priority: HIGHEST                                      │
│                     Goal: Minimize transition gap                          │
│                                                                            │
│  PHASE 3: BACKGROUND WATERMARK (Continuous)                               │
│  ═══════════════════════════════════════════                              │
│                                                                            │
│  Triggered when: bufferedAheadMs < lowWatermarkMs (10 seconds)           │
│                                                                            │
│  _startPrefetchIfNeeded() ──▶ shouldPrefetch() ──▶ calculateTargetIndex()│
│                               │                     │                      │
│                               │                     └─ Target: enough for │
│                               │                        30s buffer         │
│                               └─ runPrefetch()                            │
│                                  │                                        │
│                                  └─ Loop: synthesize until target reached │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Prefetch Decision Logic

```dart
shouldPrefetch(queue, currentIndex, playbackRate):
  // Check resource constraints
  if (!resourceMonitor.canPrefetch) → return false
  
  // Check if suspended (user interaction)
  if (isSuspended) → return false
  
  // Check if already running
  if (isRunning) → return false
  
  // Check buffer level
  bufferedMs = estimateBufferedAheadMs(queue, currentIndex)
  return bufferedMs < lowWatermarkMs  // e.g., < 10 seconds
```

### Buffer Estimation

```dart
estimateBufferedAheadMs(queue, currentIndex):
  ms = 0
  for i in (currentIndex + 1) to prefetchedThroughIndex:
    ms += estimateDurationMs(queue[i].text)  // ~150ms per word
  return ms
```

---

## Cache System

### Cache Key Generation

```
┌────────────────────────────────────────────────────────────────────────┐
│                         CACHE KEY STRUCTURE                            │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Input:                                                                │
│    voiceId = "kokoro_af"                                              │
│    text = "The quick brown fox..."                                    │
│    playbackRate = 1.5                                                 │
│                                                                        │
│  Process:                                                              │
│    1. Normalize text (trim, lowercase for hash)                       │
│    2. Always use synthesisRate = 1.0 (rate-independent caching)       │
│    3. Hash text: SHA256(normalizedText).substring(0, 16)              │
│                                                                        │
│  Output:                                                               │
│    cacheKey = "kokoro_af_1_00_a7f3b2c9d1e4f6a8"                       │
│    filename = "kokoro_af_1_00_a7f3b2c9d1e4f6a8.wav"                   │
│                                                                        │
│  Note: Rate in filename is synthesis rate (always 1.0), NOT playback  │
│        rate. Playback rate is adjusted in the audio player.           │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Cache Lookup Flow

```
synthesizeToWavFile(voiceId, text, playbackRate)
  │
  ├─ Generate cacheKey
  │
  ├─ cache.isReady(cacheKey)?
  │  │
  │  YES ──▶ cache.fileFor(cacheKey) ──▶ Return SynthResult (FAST PATH)
  │  │
  │  NO ──▶ Continue to synthesis
  │
  ├─ prepareEngine(voiceId)
  │
  ├─ engine.synthesizeToFile(...)
  │
  ├─ cache.markUsed(cacheKey)  // Update LRU timestamp
  │
  └─ Return SynthResult
```

### Cache Validity Check

```dart
isReady(cacheKey):
  file = fileFor(cacheKey)
  
  if (!file.exists()) → return false
  
  // WAV header is 44 bytes minimum
  if (file.lengthSync() < 44) → return false
  
  return true
```

---

## Engine Coordination

### Engine Routing

```
┌────────────────────────────────────────────────────────────────────────┐
│                         ENGINE ROUTING                                 │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  voiceId format: "{engine}_{voice}"                                   │
│  Examples: "kokoro_af", "piper_lessac", "supertonic_v1"              │
│                                                                        │
│  RoutingEngine._prepareEngineForVoice(voiceId):                       │
│    │                                                                   │
│    ├─ Parse engine type from voiceId                                  │
│    │                                                                   │
│    ├─ EngineMemoryManager.prepareForEngine(engineType)                │
│    │  │                                                                │
│    │  └─ May unload other engines to free memory                      │
│    │     (active engine pattern: only 1 engine loaded at a time)      │
│    │                                                                   │
│    └─ Return appropriate engine instance                              │
│       ├─ kokoroEngine (high quality, slower)                         │
│       ├─ piperEngine (fast, smaller models)                          │
│       └─ supertonicEngine (advanced features)                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Memory Management

```
┌────────────────────────────────────────────────────────────────────────┐
│                     ENGINE MEMORY BUDGET                               │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Device RAM        │ Max Loaded Models │ Strategy                     │
│  ──────────────────┼───────────────────┼──────────────────────────────│
│  ≤ 4GB             │ 1 model           │ Unload on engine switch      │
│  4-8GB             │ 2 models          │ LRU eviction                 │
│  > 8GB             │ 3+ models         │ Full caching                 │
│                                                                        │
│  EngineMemoryManager Flow:                                            │
│    prepareForEngine(engineType)                                        │
│      │                                                                 │
│      ├─ If target engine already loaded → return                      │
│      │                                                                 │
│      ├─ If budget exceeded → unloadLeastUsedEngine()                  │
│      │                                                                 │
│      └─ Mark target engine as active                                  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Concurrent Synthesis

### Android Native (Semaphore-based)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    NATIVE CONCURRENCY CONTROL                          │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Each TTS Service (Kokoro, Piper, Supertonic):                        │
│                                                                        │
│    private val synthesisSemaphore = Semaphore(4)                      │
│                                                                        │
│    synthesize(request):                                                │
│      │                                                                 │
│      ├─ if (!synthesisSemaphore.tryAcquire()) → return BUSY          │
│      │                                                                 │
│      ├─ try:                                                          │
│      │    runInference(...)                                           │
│      │                                                                 │
│      └─ finally:                                                       │
│           synthesisSemaphore.release()                                │
│                                                                        │
│  Thread Safety:                                                        │
│    - activeJobs: ConcurrentHashMap                                    │
│    - loadedVoices: ConcurrentHashMap                                  │
│    - @Volatile for isInitialized, inference fields                    │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Flutter Prefetch (Sequential with Context Check)

```dart
runPrefetch(queue, targetIndex, shouldContinue):
  isRunning = true
  
  try:
    for i in (prefetchedThroughIndex + 1) to targetIndex:
      
      // Check cancellation
      if (!shouldContinue() || contextChanged) → return
      
      track = queue[i]
      
      // Check cache
      if (await cache.isReady(cacheKey)) → 
        prefetchedThroughIndex = i
        continue
      
      // Synthesize (awaited sequentially)
      await engine.synthesizeToWavFile(...)
      prefetchedThroughIndex = i
      
  finally:
    isRunning = false
```

---

## Error Handling

### Error Types

| Error | Cause | Recovery |
|-------|-------|----------|
| `modelMissing` | TTS core not installed | UI prompts download |
| `modelCorrupted` | SHA256 mismatch | Re-download core |
| `outOfMemory` | Engine memory exhausted | Unload models, retry |
| `inferenceFailed` | Model crashed | Retry or switch voice |
| `timeout` | >30s synthesis | Retry with extension |
| `invalidInput` | Empty text | Skip segment |
| `fileWriteError` | Disk full | Retry or clear cache |
| `cancelled` | User cancelled | Stop cleanly |
| `busy` | Semaphore full | Return error code |

### Retry Logic

```
┌────────────────────────────────────────────────────────────────────────┐
│                         RETRY FLOW                                     │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Synthesis attempt                                                     │
│    │                                                                   │
│    ├─ SUCCESS → Return result                                         │
│    │                                                                   │
│    └─ FAILURE                                                          │
│         │                                                              │
│         ├─ Is retryable error? (timeout, inference, busy)             │
│         │    │                                                         │
│         │    YES ─┬─ retryAttempt < maxRetries (1)?                   │
│         │         │    │                                               │
│         │         │    YES → Increment retryAttempt, re-queue         │
│         │         │    │                                               │
│         │         │    NO → Surface error to user                      │
│         │         │                                                    │
│         │    NO ──┴─ Surface error immediately                        │
│         │                                                              │
│         └─ Log error, update UI state                                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `lowWatermarkMs` | 10,000 | Start prefetch when buffer below this |
| `bufferTargetMs` | 30,000 | Target buffer amount |
| `maxPrefetchTracks` | 15 | Max segments in prefetch batch |
| `prefetchResumeDelay` | 500ms | Resume delay after user interaction |
| `seekDebounce` | 500ms | Debounce rapid seek operations |
| `nativeSemaphoreLimit` | 4 | Max concurrent native synthesis |
| `cacheBudgetMB` | 500 | Max cache size |
| `cacheMaxAgeDays` | 7 | Prune older entries |

---

## Timing Diagram

```
Time →
────────────────────────────────────────────────────────────────────────────

User taps Play on Segment 0
│
▼
loadChapter(autoPlay=true)
│
├──────────────────── SmartSynthesisManager ────────────────────┐
│ Pre-synth S0 (blocking)                                       │
│ ████████████████████ (500ms)                                  │
│                      └── S0 READY                             │
│                          Fire S1 background synth ──────────┐ │
│                                                              │ │
└─────────────────── _speakCurrent(S0) ───────────────────────┼─┘
                    │                                          │
                    └── playFile(S0) starts                    │
                        │                                      │
                        ├── _startImmediateNextPrefetch(S1) ◀──┤
                        │   S1 already in progress, skip       │
                        │                                      │
                        ├── _startPrefetchIfNeeded()           │
                        │   Buffer: ~8s (S1 estimated)         │
                        │   < 10s threshold → start prefetch   │
                        │                                      │
                        └── runPrefetch(target=S5)             │
                            ██████ S2 (200ms)                  │
                            ██████ S3 (180ms)          S1 done ┘
                            ██████ S4 (220ms)
                            ██████ S5 (190ms)
                            └── prefetchedThroughIndex = 5

S0 audio plays for ~8 seconds...
│
▼
AudioEvent.completed → nextTrack()
│
└── _speakCurrent(S1)
    │
    └── S1 READY (cache hit) → instant playback
        │
        └── _startImmediateNextPrefetch(S2)
            S2 READY (cache hit) → skip
            
... continuous loop ...
```

---

## Implementation Files

| File | Purpose |
|------|---------|
| `buffer_scheduler.dart` | Prefetch orchestration, watermark logic |
| `smart_synthesis_manager.dart` | Pre-playback synthesis strategy |
| `routing_engine.dart` | Engine selection, cache integration |
| `audio_cache.dart` | File caching, LRU management |
| `cache_key_generator.dart` | Deterministic key generation |
| `playback_controller.dart` | Coordinates synthesis with playback |
| `KokoroTtsService.kt` | Native Kokoro synthesis with semaphore |
| `PiperTtsService.kt` | Native Piper synthesis with semaphore |
| `SupertonicTtsService.kt` | Native Supertonic synthesis |
