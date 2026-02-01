# Audio Synthesis Pipeline

> Transforms text segments into playable audio with intelligent prefetching.

## Overview

The synthesis pipeline:
1. Converts text segments to audio via on-device TTS engines
2. Caches synthesized audio for instant replay
3. Prefetches upcoming segments to eliminate playback gaps
4. Manages memory across Kokoro, Piper, and Supertonic engines

---

## Architecture

```mermaid
flowchart TB
    subgraph Playback["Playback Layer"]
        PM[PlaybackViewNotifier]
        BS[BufferScheduler]
    end
    
    subgraph Synthesis["Synthesis Layer"]
        SSM[SmartSynthesisManager]
        RE[RoutingEngine]
        Cache[AudioCache]
    end
    
    subgraph TTS["TTS Engines (Native)"]
        Kokoro
        Piper
        Supertonic
    end
    
    PM --> BS
    BS --> SSM
    SSM --> RE
    RE --> Cache
    RE --> Kokoro
    RE --> Piper
    RE --> Supertonic
```

---

## Segment Lifecycle

```mermaid
stateDiagram-v2
    [*] --> NOT_QUEUED
    NOT_QUEUED --> QUEUED: enters prefetch window
    QUEUED --> SYNTHESIZING: synthesis starts
    SYNTHESIZING --> READY: success
    SYNTHESIZING --> FAILED: error
    FAILED --> QUEUED: retry
    READY --> [*]
```

| State | Description |
|-------|-------------|
| `NOT_QUEUED` | Beyond prefetch window |
| `QUEUED` | Waiting for synthesis slot |
| `SYNTHESIZING` | TTS engine processing |
| `READY` | Cached and playable |
| `FAILED` | Error (may retry) |

---

## Segment Readiness Tracker (UI Feedback)

The `SegmentReadinessTracker` provides real-time UI feedback for segment synthesis status.

### State to Opacity Mapping

| State         | Opacity | Visual Effect                    |
|---------------|---------|----------------------------------|
| `notQueued`   | 0.3     | Very faded (grey)                |
| `queued`      | 0.4     | Faded                            |
| `synthesizing`| 0.6→1.0 | Interpolates based on progress   |
| `ready`       | 1.0     | Fully visible                    |
| `error`       | 1.0     | Fully visible (error styling)    |

### Readiness Key Format

```
"{bookId}:{chapterIndex}"
```

**Important:** The readiness key does NOT include voiceId. Cache keys DO include voiceId.
This means when voice changes, readiness must be reset (see Voice Change Handling below).

### Events

| Event                   | From          | To            | Trigger                          |
|-------------------------|---------------|---------------|----------------------------------|
| `onSegmentQueued()`     | notQueued     | queued        | BufferScheduler adds to queue    |
| `onSynthesisStarted()`  | queued        | synthesizing  | SynthesisCoordinator starts      |
| `onSynthesisProgress()` | synthesizing  | synthesizing  | TTS engine reports progress      |
| `onSynthesisComplete()` | synthesizing  | ready         | Audio cached successfully        |
| `onSynthesisError()`    | synthesizing  | error         | Synthesis failed                 |
| `initializeFromCache()` | any           | ready         | Cache hit on chapter load        |
| `reset()`               | any           | cleared       | Voice change or chapter change   |

### Implementation

```dart
// lib/app/playback_providers.dart
class SegmentReadinessTracker {
  static final instance = SegmentReadinessTracker._();
  
  final Map<String, Map<int, SegmentReadiness>> _readiness = {};
  
  // Update on synthesis events
  void onSynthesisStarted(String key, int index);
  void onSynthesisComplete(String key, int index);
  
  // Reset when voice or chapter changes
  void reset(String key);
  
  // Get current state for UI
  Map<int, SegmentReadiness> getReadiness(String key);
}
```

---

## Voice Change Handling

When user changes voice during playback:

```mermaid
sequenceDiagram
    participant User
    participant VoiceListener
    participant PlaybackController
    participant SynthesisCoordinator
    participant ReadinessTracker
    participant Cache
    
    User->>VoiceListener: Select new voice
    VoiceListener->>PlaybackController: notifyVoiceChanged()
    PlaybackController->>SynthesisCoordinator: reset()
    Note over SynthesisCoordinator: Cancel pending synthesis
    VoiceListener->>ReadinessTracker: reset(key)
    Note over ReadinessTracker: Clear all readiness state
    VoiceListener->>Cache: Re-check with new voiceId
    Note over Cache: Find segments already<br/>cached for new voice
    ReadinessTracker-->>User: UI updates to show<br/>correct readiness
```

### Why Reset is Required

Cache keys include voiceId:
```
kokoro_af_bella_1.00_a1b2c3d4e5f6.wav
piper:en_US-lessac_1.00_a1b2c3d4e5f6.wav  // Same text, different voice
```

When voice changes:
1. Old voice's segments show as "ready" (opacity 1.0)
2. But cache lookup uses new voiceId → won't find old entries
3. **Result:** UI lies about which segments are ready

**Solution:** Reset readiness on voice change, then re-check cache with new voiceId.

---

## Prefetch Strategy

### Three-Phase Prefetch

| Phase | Trigger | Target | Priority |
|-------|---------|--------|----------|
| **Cold-start** | `loadChapter()` | Segment 0 (blocking) + 1 (async) | Highest |
| **Immediate** | `playFile(n)` | Segment n+1 | High |
| **Background** | Buffer < 10s | Until 30s buffer | Normal |

### Strategy Selection

```mermaid
flowchart TD
    Start[Check Device State]
    Start --> LowPower{Low Power Mode?}
    LowPower -->|Yes| Conservative[Conservative: 1-2 segments]
    LowPower -->|No| Charging{Charging?}
    Charging -->|Yes| Aggressive[Aggressive: 5+ segments]
    Charging -->|No| Adaptive[Adaptive: RTF-based, 2-4 segments]
```

---

## Cache System

### Cache Key Structure
```
{engine}_{voice}_{rate}_{textHash}
Example: kokoro_af_1_00_a7f3b2c9d1e4f6a8.wav
```

- Rate is synthesis rate (always 1.0), NOT playback rate
- Playback rate adjusted in audio player
- Cache validated: file exists + length >= 44 bytes (WAV header)

### Cache Lookup Flow
```
synthesize(voiceId, text)
  → Generate cacheKey
  → cache.isReady(cacheKey)?
      YES → Return cached file (FAST PATH)
      NO  → Synthesize → cache.markUsed() → Return
```

---

## Engine Management

### Engine Routing
```dart
voiceId format: "{engine}_{voice}"
Examples: "kokoro_af", "piper_lessac", "supertonic_v1"
```

### Memory Budget

| Device RAM | Max Loaded | Strategy |
|------------|------------|----------|
| ≤ 4GB | 1 model | Unload on switch |
| 4-8GB | 2 models | LRU eviction |
| > 8GB | 3+ models | Full caching |

---

## Concurrency Control

### Native Layer (Kotlin)
```kotlin
// Each TTS service limits to 4 concurrent requests
private val synthesisSemaphore = Semaphore(4)

synthesize(request):
    if (!synthesisSemaphore.tryAcquire()) → return BUSY
    try { runInference(...) }
    finally { synthesisSemaphore.release() }
```

### Flutter Layer
- Sequential prefetch with cancellation checks
- Context change → abort all pending synthesis
- Cancel token propagated to native layer

---

## Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `modelMissing` | TTS not installed | Prompt download |
| `outOfMemory` | Engine memory exhausted | Unload models, retry |
| `inferenceFailed` | Model crashed | Retry or skip |
| `busy` | Semaphore full | Return error code |
| `cancelled` | User cancelled | Stop cleanly |

### Retry Logic
- Retryable: timeout, inference, busy
- Max retries: 1
- Non-retryable: missing model, corrupted, invalid input

---

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `lowWatermarkMs` | 10,000 | Start prefetch threshold |
| `bufferTargetMs` | 30,000 | Target buffer size |
| `maxPrefetchTracks` | 15 | Max batch size |
| `nativeSemaphoreLimit` | 4 | Concurrent native synthesis |
| `cacheBudgetMB` | 500 | Max cache size |

---

## Implementation Files

| File | Purpose |
|------|---------|
| `buffer_scheduler.dart` | Prefetch orchestration |
| `smart_synthesis_manager.dart` | Cold-start strategy |
| `routing_engine.dart` | Engine selection |
| `audio_cache.dart` | File caching |
| `playback_view_notifier.dart` | Playback state machine |
| `*TtsService.kt` | Native synthesis |
