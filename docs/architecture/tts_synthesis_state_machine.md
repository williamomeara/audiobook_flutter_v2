# TTS Synthesis State Machine

This document describes the state machine governing text-to-speech synthesis in the audiobook app.

## Overview

The TTS system uses a multi-layered state machine architecture:

1. **Core Readiness** - Engine initialization lifecycle
2. **Voice Readiness** - Voice/speaker availability  
3. **Synthesis Lifecycle** - Per-synthesis request stages

## State Diagrams

### Core Readiness State Machine

```
┌─────────────┐
│ NOT_STARTED │
└──────┬──────┘
       │ Core files missing
       ▼
┌─────────────┐
│ DOWNLOADING │◄────────────┐
└──────┬──────┘             │
       │ Download complete   │ Retry
       ▼                     │
┌─────────────┐              │
│ EXTRACTING  │              │
└──────┬──────┘              │
       │ Extraction complete  │
       ▼                     │
┌─────────────┐              │
│  VERIFYING  │──────────────┤
└──────┬──────┘   Verify     │
       │          failed     │
       │ Files valid         │
       ▼                     │
┌─────────────┐              │
│   LOADED    │              │
└──────┬──────┘              │
       │ initEngine()        │
       ▼                     │
┌─────────────┐  ┌────────┐  │
│    READY    │  │ FAILED │◄─┘
└─────────────┘  └────────┘
                 (Permanent - user action required)
```

### Voice Readiness State Machine

```
┌──────────┐
│ CHECKING │
└────┬─────┘
     │
     ├─ Core not loaded ─────────────┐
     │                               ▼
     │                        ┌──────────────┐
     │                        │ CORE_REQUIRED│
     │                        └──────┬───────┘
     │                               │ Download started
     │                               ▼
     │                        ┌──────────────┐
     │                        │ CORE_LOADING │
     │                        └──────┬───────┘
     │                               │ Core ready
     │                               │
     │ Voice available ◄─────────────┘
     ▼
┌─────────────┐      ┌───────┐
│ VOICE_READY │      │ ERROR │
└─────────────┘      └───────┘
                     (Permanent)
```

### Synthesis Lifecycle State Machine

```
┌──────────┐
│  QUEUED  │ ◄─────────────────────────────────────┐
└────┬─────┘                                       │
     │ Acquired from pool                          │
     ▼                                             │
┌─────────────┐                                    │
│ VOICE_READY │ Verify voice loaded                │
└────┬────────┘                                    │
     │                                             │
     ├─ Voice not loaded ─► Load voice             │
     │                                             │
     │ Voice loaded                                │
     ▼                                             │
┌─────────────┐                                    │
│ INFERENCING │ Running model inference            │
└──────┬──────┘                                    │
       │                                           │
       ├──────── OutOfMemory ───► Unload LRU ──────┘
       │                          (retry if canRetry)
       │ Inference complete
       ▼
┌─────────────┐
│ WRITING_FILE│ Converting samples to WAV
└──────┬──────┘
       │ File written
       ▼
┌─────────────┐
│ CACHE_MOVING│ Atomic rename: .tmp → final
└──────┬──────┘
       │ Move complete
       ▼
┌──────────┐
│ COMPLETE │
└──────────┘

Error/Cancel flows:
- Any state ──(user cancel)──► CANCELLED
- Any state ──(fatal error)──► FAILED
```

## States Reference

### Core Readiness States

| State | Description |
|-------|-------------|
| `notStarted` | Initial state, no core files present |
| `downloading` | Downloading core model files |
| `extracting` | Extracting downloaded archive |
| `verifying` | Verifying file integrity |
| `loaded` | Files present, engine not yet initialized |
| `ready` | Engine initialized and ready |
| `failed` | Permanent failure - requires user action |

### Voice Readiness States

| State | Description |
|-------|-------------|
| `checking` | Checking voice availability |
| `coreRequired` | Core must be downloaded first |
| `coreLoading` | Core download in progress |
| `voiceReady` | Voice loaded and ready for synthesis |
| `error` | Voice cannot be loaded |

### Synthesis Lifecycle States

| State | Description |
|-------|-------------|
| `queued` | Waiting in synthesis pool |
| `voiceReady` | Verifying voice is loaded |
| `inferencing` | Running TTS model inference |
| `writingFile` | Writing PCM samples to WAV |
| `cacheMoving` | Atomic rename to final path |
| `complete` | Synthesis succeeded |
| `failed` | Synthesis failed |
| `cancelled` | User cancelled request |

## Error Codes

| Code | Description | Recoverable |
|------|-------------|-------------|
| `modelMissing` | Model file not found | No - needs download |
| `modelCorrupted` | Model file corrupted | No - needs re-download |
| `inferenceFailed` | Inference error | Maybe - retry |
| `runtimeCrash` | Native crash | No |
| `cancelled` | User cancellation | N/A |
| `invalidInput` | Empty/invalid text | No |
| `fileWriteError` | Failed to write output | No |
| `outOfMemory` | OOM during inference | Yes - unload LRU |
| `busy` | Too many concurrent requests | Yes - retry later |
| `unknown` | Unknown error | No |

## Transition Triggers

| Trigger | From | To | Handler |
|---------|------|-----|---------|
| Core not found | `notStarted` | `downloading` | Download manager |
| Download complete | `downloading` | `extracting` | Archive extractor |
| Extraction complete | `extracting` | `verifying` | Integrity checker |
| Files valid | `verifying` | `loaded` | State manager |
| `initEngine()` | `loaded` | `ready` | Native API |
| `loadVoice()` | `coreReady` | `voiceReady` | Service |
| `synthesize()` | `voiceReady` | `inferencing` | Native synthesis |
| Inference done | `inferencing` | `writingFile` | WAV writer |
| File written | `writingFile` | `cacheMoving` | Atomic mover |
| Move complete | `cacheMoving` | `complete` | Callback |
| User cancel | Any active | `cancelled` | `cancelSynth()` |
| Fatal error | Any active | `failed` | Error handler |
| OOM + retry | `failed` | `queued` | LRU unloader |

## Architecture Layers

### Flutter (Dart) Layer

```
┌────────────────────────────────────────────────┐
│                  RoutingEngine                 │
│         Routes requests by voiceId             │
└──────────────────┬─────────────────────────────┘
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
┌────────────┐ ┌────────────┐ ┌────────────────┐
│  Kokoro    │ │   Piper    │ │   Supertonic   │
│  Adapter   │ │  Adapter   │ │    Adapter     │
└─────┬──────┘ └─────┬──────┘ └───────┬────────┘
      │              │                │
      └──────────────┼────────────────┘
                     ▼
           ┌────────────────────┐
           │  TtsNativeApi      │
           │  (Method Channel)  │
           └────────────────────┘
```

### Android (Kotlin) Layer

```
┌────────────────────────────────────────────────┐
│              TtsNativeApiImpl                  │
│   - Request ownership tracking                 │
│   - Routes to correct service                  │
└──────────────────┬─────────────────────────────┘
                   │
       ┌───────────┼───────────────┐
       ▼           ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ KokoroTts    │ │  PiperTts    │ │ SupertonicTts│
│ Service      │ │  Service     │ │  Service     │
│ (:kokoro)    │ │  (:piper)    │ │ (:supertonic)│
└──────────────┘ └──────────────┘ └──────────────┘
     │                 │                 │
     ▼                 ▼                 ▼
   sherpa-onnx     sherpa-onnx      ONNX Runtime
```

## Concurrency & Resource Management

### Semaphore Limiting

Each TTS service limits concurrent synthesis to 4 requests:

```kotlin
private val synthesisPermits = Semaphore(4)

suspend fun synthesize(...): SynthesisResult {
    if (!synthesisPermits.tryAcquire()) {
        return SynthesisResult(
            success = false,
            errorCode = ErrorCode.BUSY,
            errorMessage = "Too many concurrent synthesis requests"
        )
    }
    try {
        // synthesis logic
    } finally {
        synthesisPermits.release()
    }
}
```

### Thread Safety

All shared state uses thread-safe collections:

```kotlin
private val activeJobs = ConcurrentHashMap<String, Job>()
private val loadedVoices = ConcurrentHashMap<String, VoiceInfo>()
@Volatile private var isInitialized = false
```

### Memory Management

LRU-based model unloading on memory pressure:

1. Check `isSafeToLoadModel()` before loading
2. On OOM: Call `unloadLeastUsedVoice()` → retry
3. Track `lastUsed` timestamp on each voice
4. `SynthesisCounter` prevents unload during active synthesis

## Cancellation Flow

```
Flutter                    Android
   │                          │
   │  cancelSynth(reqId)      │
   │─────────────────────────►│
   │                          │ Lookup owner in requestOwners
   │                          │ Remove from map (race-safe)
   │                          │ Cancel job
   │                          │ Clean up .tmp file
   │                          │
   │  ExtendedSynthResult     │
   │◄─────────────────────────│
   │  (cancelled=true)        │
```

## File Operation Safety

Synthesis output uses atomic file operations:

```kotlin
val tmpFile = File("$outputPath.tmp")

// Create parent directories with validation
val parentDir = tmpFile.parentFile
if (parentDir != null && !parentDir.exists() && !parentDir.mkdirs()) {
    throw IOException("Failed to create output directory")
}

writeWavFile(tmpFile, pcmData, sampleRate)

// Atomic rename with fallback
val finalFile = File(outputPath)
if (!tmpFile.renameTo(finalFile)) {
    // Fallback for cross-filesystem moves
    tmpFile.copyTo(finalFile, overwrite = true)
    tmpFile.delete()
}
```

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md) - High-level system architecture
- [Playback State Machine](./playback_screen_state_machine.md) - Playback navigation states
