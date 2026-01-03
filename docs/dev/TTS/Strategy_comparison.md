# Strategy Comparison: Original vs Improved

## Summary of Improvements

The **Improved Strategy** is a production-hardened version of the original, with these key enhancements:

---

## Key Differences

| Aspect | Original Strategy | Improved Strategy |
|--------|------------------|-------------------|
| **Approach** | Theoretical roadmap | Practical implementation with checkpoints |
| **Upfront Tests** | None (run during phases) | 3 critical risk tests FIRST (2-3 hours) |
| **Architecture Decision** | Assumed single process | Tests decide: Option A vs B |
| **API Design** | Generic interfaces | State machines for reliability |
| **Asset Pipeline** | Basic download | Atomic .tmp → rename (corruption-safe) |
| **Testing** | Per-phase | Per-phase + perf targets + stress tests |
| **Risk Mitigation** | Implicit | Explicit table of 8 risks + mitigations |
| **Model Caching** | Simple LRU | Device-aware + memory pressure handling |
| **Cancellation** | Best-effort opId guard | opId + explicit cancel() + .tmp cleanup |
| **Duration** | 3-4 weeks | 4-5 weeks (more realistic) |
| **Phases** | 10 phases | 10 phases with detailed checklists |

---

## What Got Added (New Content)

### 1. **Upfront Risk Tests (Section 1)**
Three tests that run BEFORE Phase 1:
- **Model Coexistence Test** (30 min) → Decides Option A vs B
- **Audio Format Validation** (30 min) → Confirms WAV correctness
- **Cancellation Safety Test** (30 min) → Verifies no partial files

**Why:** These tests unlock architecture decisions early, preventing wasted work.

### 2. **State Machines (Section 2)**
Replaces vague "ready/not ready" with explicit finite state machines:

```
CoreReadyState: notStarted → downloading → extracting → verifying → loaded → ready
VoiceReadyState: checking → coreRequired → coreLoading → voiceReady → error
SynthStage: queued → voiceReady → inferencing → writingFile → cacheMoving → complete
```

**Why:** UI can show exact progress. No ambiguous "is it loading?"

### 3. **Decision Matrix (Section 0)**
Fill in ONE page before day 1:
- Process model (A or B)
- Sample rate
- Model caching strategy
- First engine to target
- Voice selection

**Why:** Prevents "what do we do?" mid-implementation.

### 4. **Atomic Download Pattern (Section 3.2)**

```
download → tmpFile → extract → tmpDir → verify → rename (atomic)
```

**Benefits:**
- Corruption-safe (never partial core on disk)
- Resumable (tmpFile.exists() = continue)
- Rollback-capable (rename is atomic, can't leave broken state)

### 5. **Platform Channel Contract (Pigeon) (Section 2.4)**

Clear, type-safe interface definition using Pigeon:
```dart
@HostApi()
abstract class TtsNativeApi {
  Future<void> initEngine(String engineType, String corePath);
  Future<Map<String, Object?>> synthesize(...);
  Future<void> cancelSynth(String requestId);
  Future<int> getAvailableMemoryMB();
}
```

**Why:** 
- Auto-generates Kotlin stubs (zero boilerplate)
- Type-safe (no string keys)
- Version-aware (Pigeon handles API evolution)

### 6. **Model Caching Manager (Phase 6, Section 4)**

Explicit LRU with device awareness:
```dart
- Low-end (4GB): Keep 1 model max
- High-end (12GB): Keep 3 models max
- Pressure: Unload LRU if available < 100MB
```

**Why:** Prevents OOM crashes on low-end devices without punishing high-end.

### 7. **Piper Phonemizer Integration (Phase 7)**

Explicit handling of Piper's unique requirement:
```dart
final phonemes = await _phonemizer.phonemize(normalizedText);
final result = await _channel.synthesize(
  engineType: 'piper',
  phonemes: phonemes,  // ← Piper input, not raw text
  ...
);
```

**Why:** Piper needs phonemes, not text. Must be in adapter, not generic code.

### 8. **Error Recovery Map (Section 5)**

Each error has explicit recovery:
| Error | Recovery |
|-------|----------|
| MODEL_MISSING | Auto-download + UI progress |
| OUT_OF_MEMORY | Unload least-used + retry once |
| SERVICE_DEAD | Rebind + retry once |

**Why:** No guessing. Every error has a defined recovery path.

### 9. **Performance Targets (Phase 10)**

Concrete metrics to hit:
- Cold synth <5s (Kokoro INT8)
- Warm cache <500ms
- Memory peak <300MB
- Crash rate <0.1%

**Why:** Prevents shipping slow/buggy code.

### 10. **Known Risks Table (Section 7)**

7 risks explicitly listed with mitigations:
- Native lib conflicts (test early)
- Audio format mismatch (validate early)
- Cancellation races (.tmp protocol)
- Memory bloat (LRU unload)
- Piper phonemizer (Phase 2 resolve)
- Model corruption (atomic rename)
- Native runtime crash (Binder death detection)

**Why:** No surprises. Known risks = managed risks.

---

## What Changed (Improvements to Original)

### Phase 1: EARLIER & TIGHTER
**Original:** Monorepo setup, scaffold (Days 1-2)
**Improved:** Risk tests + decisions (Days 1-2) → locks architecture early

### Phase 2: EXPLICIT STATE MACHINES
**Original:** Vague "ensure ready" methods
**Improved:** CoreReadyState + VoiceReadyState streams → UI can show exact progress

### Phase 3-4: MORE DETAIL
**Original:** Generic "implement storage"
**Improved:** Atomic .tmp pattern, SHA256 verification, manifest format specified

### Phase 5: KOKORO FIRST
**Original:** Generic "single engine"
**Improved:** Kokoro specifically (simplest to get working) + memory management

### Phase 7-8: PHONEMIZER EXPLICIT
**Original:** Generic adapter pattern
**Improved:** Piper's phonemizer requirement explicitly handled in adapter

### Phase 9: BUFFER SCHEDULER INTEGRATION
**Original:** Generic buffer scheduler
**Improved:** Sample rate in cache key, explicit opId tracking

### Phase 10: PERFORMANCE TARGETS
**Original:** Generic "performance hardening"
**Improved:** Concrete metrics + stress tests + golden file tests

---

## New Testing Approach

**Original:** Each phase has unit tests (implicit)
**Improved:** 
- Pre-phase tests (Section 1) unlock decisions
- Per-phase checklists with specific test commands
- End-to-end integration tests (import → synth → play)
- Stress tests (50 rapid requests)
- Performance metrics (latency, memory, crash rate)

---

## Why This Matters for Your AI Agent

When sending to your AI agent (GPT-5.2), the **Improved Strategy** provides:

1. **Explicit decision points** → No ambiguity
2. **Concrete test procedures** → "Run this, see if it passes"
3. **State machine clarity** → UI always knows exact state
4. **Risk mitigation first** → Prevents rework
5. **Phase-by-phase checklists** → Track progress
6. **Platform-agnostic core + platform-specific adapters** → Clean architecture
7. **Performance targets** → Success criteria defined upfront
8. **Error recovery map** → Every error has a path forward

**The agent can start Phase 1 Day 1 immediately without questions.**

---

## Migration Path (If You Start With Original)

If you already started with the original strategy:

1. **Completed Phase 1?** → Run risk tests (Section 1) immediately (2-3 hours)
2. **Running Phase 2?** → Pause, add state machines (Section 2), resume
3. **At Phase 3?** → Adopt atomic .tmp pattern (Section 3.2) before continuing
4. **At Phase 5?** → Use DeviceProfile + model cache manager (Section 4)

**No wasted work.** The improved strategy is a superset with extra guardrails.

---

## Recommended Starting Point

**Send to your AI agent:**

1. This document (strategy comparison)
2. The full improved strategy (TTS_implementation_improved.md)
3. The current Phase-by-Phase Execution (from your canvas - for reference)
4. Your decision matrix filled in (Section 0)

**Agent should start:** Phase 1 (Risk tests + decisions) immediately.

---

**Timeline:** 4-5 weeks to production-ready TTS with all 3 engines on Android.
