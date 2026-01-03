# TTS Implementation Decisions

**Date:** 2026-01-03
**Status:** Locked

---

## Decision Matrix

### PROCESS MODEL
**Decision:** Multi-process (Option B)
- Each engine runs in its own Android process (`:kokoro`, `:piper`, `:supertonic`)
- Provides complete isolation to avoid native lib conflicts
- Uses Android Binder IPC for communication

### AUDIO FORMAT
**Decision:** 24000 Hz sample rate
- Mono (1 channel)
- 16-bit PCM
- WAV format for caching
- just_audio handles playback resampling

### MODEL CACHING
**Decision:** Device-aware loading
- Low-end device (4GB RAM): Keep 1 model loaded max
- Mid device (8GB RAM): Keep 2 models loaded max
- High-end device (12GB+ RAM): Keep 3 models loaded max
- LRU eviction when memory pressure detected

### ENGINE PRIORITY
**Decision:** Implement all three engines
1. Kokoro (first) - simpler, fewer dependencies
2. Piper (second) - requires phonemizer toolchain
3. Supertonic (third) - needs speaker embeddings

### ERROR RECOVERY
| Error | Recovery Action |
|-------|-----------------|
| Model missing | Auto-download now + show UI progress |
| Inference fails (OOM) | Unload least-used model, retry once |
| Native runtime crash | Rebind service + retry once (max) |

### VOICE SELECTION (Testing)
Selected voices for initial testing:
- `kokoro_af` - Kokoro American Female (default)
- `kokoro_bf_emma` - Kokoro British Female Emma
- `piper:en_GB-alan-medium` - Piper Alan (British Male)

### MODEL FILES
- Pre-staged in test fixtures for development
- Production: Hosted on CDN with SHA256 verification

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                 Main App Process                     │
│  ┌─────────────────────────────────────────────────┐ │
│  │ Flutter App (Dart)                               │ │
│  │ ├─ TTS Engine Adapters                          │ │
│  │ ├─ Synthesis Pool                               │ │
│  │ └─ Buffer Scheduler                             │ │
│  └─────────────────────────────────────────────────┘ │
│                      │ MethodChannel/Binder          │
└──────────────────────┼──────────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  :kokoro    │ │   :piper    │ │ :supertonic │
│  process    │ │   process   │ │   process   │
│             │ │             │ │             │
│ KokoroSvc   │ │ PiperSvc    │ │ SuperSvc    │
│ ONNX Runtime│ │ ONNX Runtime│ │ ONNX Runtime│
└─────────────┘ └─────────────┘ └─────────────┘
```

---

## State Machines

### Core Ready State
```
notStarted → downloading → extracting → verifying → loaded → ready
                 ↓              ↓           ↓
              failed        failed      failed
```

### Voice Ready State
```
checking → coreRequired → coreLoading → voiceReady
    ↓                                        ↓
  error                                   error
```

### Synthesis Stage
```
queued → voiceReady → inferencing → writingFile → cacheMoving → complete
                                                       ↓
                                                  cancelled/failed
```

---

## Performance Targets

| Metric | Target |
|--------|--------|
| Cold synth (no cache) | < 5 seconds |
| Warm synth (cache hit) | < 500ms |
| Memory peak | < 300MB per engine |
| Cache hit rate | > 90% |
| Crash rate | < 0.1% |
