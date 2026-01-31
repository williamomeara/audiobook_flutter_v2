# TTS State Machine Audit Report

**Date:** January 2026  
**Auditor:** AI Assistant  
**Scope:** Review state machine implementations across Flutter (Dart) and Android (Kotlin) layers

## Executive Summary

The TTS state machine implementation is **well-structured** with clear separation of concerns. However, several improvements can enhance robustness, fix gaps, and improve error handling.

### Critical Issues Found

1. **BUSY Error Code Mismatch** - Native has `BUSY` but not propagated to Flutter
2. **Missing OOM Error Type** - OOM mapped to `inferenceFailed`, losing semantic meaning
3. **No Timeout State** - Timeout errors not distinguished from general failures
4. **Inconsistent State Tracking** - Flutter adapters track state locally, can diverge from native

### Priority Improvements

| Priority | Issue | Impact | Effort |
|----------|-------|--------|--------|
| 🔴 High | BUSY error code alignment | Runtime errors | Low |
| 🔴 High | Add OOM error type | Retry logic fails | Low |
| 🟡 Medium | Timeout state handling | Poor UX on slow synthesis | Medium |
| 🟡 Medium | State sync mechanism | Stale state in UI | High |
| 🟢 Low | Progress states in synthesis | No granular progress | Medium |

---

## Detailed Findings

### 1. Error Code Alignment (🔴 CRITICAL)

**Problem:** The native Kotlin layer now returns `ErrorCode.BUSY` when synthesis semaphore is full, but this error code is not defined in:
- `packages/platform_android_tts/pigeons/tts_service.dart`
- `packages/tts_engines/lib/src/interfaces/tts_state_machines.dart`

**Current Native Code:**
```kotlin
// KokoroTtsService.kt
if (!synthesisPermits.tryAcquire()) {
    return SynthesisResult(
        success = false,
        errorCode = ErrorCode.BUSY,  // ❌ Not in Pigeon definition!
        errorMessage = "Too many concurrent synthesis requests"
    )
}
```

**Impact:** 
- BUSY error maps to UNKNOWN when crossing the Pigeon bridge
- Flutter side cannot distinguish between "try again later" vs permanent failure
- Retry logic treats BUSY as unrecoverable

**Fix:**
1. Add `busy` to `NativeErrorCode` enum in `pigeons/tts_service.dart`
2. Add `busy` to `EngineError` enum in `tts_state_machines.dart`
3. Regenerate Pigeon bindings
4. Update error mapping in adapters

---

### 2. OOM Error Lost in Translation (🔴 HIGH)

**Problem:** Out-of-memory is mapped to `inferenceFailed` in adapters:

```dart
// kokoro_adapter.dart
NativeErrorCode.outOfMemory => EngineError.inferenceFailed,  // ❌ Loses OOM semantics
```

**Impact:**
- Flutter cannot distinguish OOM from other inference failures
- OOM-specific retry logic (unload LRU model) requires string matching instead of error code
- Analytics cannot track OOM frequency separately

**Fix:**
1. Add `outOfMemory` to `EngineError` enum
2. Update all adapters to map correctly:
   ```dart
   NativeErrorCode.outOfMemory => EngineError.outOfMemory,
   ```

---

### 3. Missing Timeout Handling (🟡 MEDIUM)

**Problem:** Synthesis can timeout, but there's no explicit timeout state or error code.

**Current Flow:**
```dart
// SegmentSynthRequest has timeout
final Duration timeout;  // Default: 30s

// But no explicit handling - relies on coroutine cancellation
```

**Impact:**
- UI cannot show "synthesis taking too long" message
- No differentiation between "slow but working" and "hung"
- Cannot track timeout frequency

**Recommendation:**
1. Add `timeout` to `EngineError` enum
2. Add `SynthStage.timedOut` state
3. Implement explicit timeout tracking in adapters

---

### 4. State Synchronization Gap (🟡 MEDIUM)

**Problem:** Flutter adapters track loaded voices locally:

```dart
// kokoro_adapter.dart
final Map<String, DateTime> _loadedVoices = {};  // Local tracking
```

But native also tracks separately:
```kotlin
// KokoroTtsService.kt
private val loadedVoices = ConcurrentHashMap<String, KokoroVoice>()
```

**Impact:**
- If native unloads due to memory pressure, Flutter still thinks voice is loaded
- Race conditions between Flutter LRU and native LRU
- Stale state after app backgrounding

**Recommendation:**
1. Single source of truth: Query native for loaded state
2. Or: Add callback mechanism when native unloads voices
3. Invalidate Flutter cache on each synthesis attempt

---

### 5. Missing Progress States (🟢 LOW)

**Problem:** `SynthStage` jumps from `voiceReady` to `inferencing` with no intermediate states.

**Current Stages:**
```dart
enum SynthStage {
  queued,
  voiceReady,
  inferencing,  // ← Long gap here
  writingFile,
  cacheMoving,
  complete,
  ...
}
```

**Missing States:**
- `loadingVoice` - When voice needs to be loaded into memory
- `preparingInput` - Text preprocessing/normalization
- `generatingAudio` - During inference (could have sub-progress)

**Impact:**
- UI shows generic "processing" during long synthesis
- Cannot show progress percentage during inference

**Recommendation (Low Priority):**
```dart
enum SynthStage {
  queued,
  loadingVoice,    // NEW
  voiceReady,
  preparingInput,  // NEW (optional)
  inferencing,
  writingFile,
  cacheMoving,
  complete,
  failed,
  cancelled,
  timedOut,        // NEW
}
```

---

## Architecture Recommendations

### 1. Centralized Error Handling

Create a single error mapper that all adapters use:

```dart
// error_mapper.dart
class TtsErrorMapper {
  static EngineError fromNative(NativeErrorCode code) {
    return switch (code) {
      NativeErrorCode.none => EngineError.unknown,
      NativeErrorCode.modelMissing => EngineError.modelMissing,
      NativeErrorCode.outOfMemory => EngineError.outOfMemory,  // NEW
      NativeErrorCode.busy => EngineError.busy,                 // NEW
      // ... etc
    };
  }
  
  static bool isRetryable(EngineError error) {
    return switch (error) {
      EngineError.outOfMemory => true,  // Retry after LRU unload
      EngineError.busy => true,         // Retry after delay
      EngineError.runtimeCrash => true, // Retry once
      _ => false,
    };
  }
}
```

### 2. State Machine Validation

Add runtime assertions to catch invalid state transitions:

```dart
class StateMachineValidator {
  final Set<(SynthStage, SynthStage)> _validTransitions = {
    (SynthStage.queued, SynthStage.voiceReady),
    (SynthStage.voiceReady, SynthStage.inferencing),
    (SynthStage.inferencing, SynthStage.writingFile),
    (SynthStage.writingFile, SynthStage.cacheMoving),
    (SynthStage.cacheMoving, SynthStage.complete),
    // Error transitions from any state
    (null, SynthStage.failed),
    (null, SynthStage.cancelled),
  };
  
  void validateTransition(SynthStage? from, SynthStage to) {
    if (!_validTransitions.contains((from, to)) && 
        !_validTransitions.contains((null, to))) {
      assert(false, 'Invalid state transition: $from -> $to');
    }
  }
}
```

### 3. Native State Callbacks

Add Flutter API callback for native-initiated state changes:

```dart
// In TtsFlutterApi (Pigeon)
abstract class TtsFlutterApi {
  void onVoiceUnloaded(NativeEngineType engine, String voiceId);
  void onMemoryWarning(NativeEngineType engine, int availableMB);
  void onEngineStateChange(NativeEngineType engine, NativeCoreState state);
}
```

---

## Immediate Action Items

### Phase 1: Error Code Fix (1-2 hours)

1. Add `busy` to `NativeErrorCode` in `pigeons/tts_service.dart`
2. Add `busy`, `outOfMemory`, `timeout` to `EngineError` in `tts_state_machines.dart`
3. Regenerate Pigeon bindings: `flutter pub run pigeon`
4. Update error mapping in all adapters
5. Update TtsNativeApiImpl.kt error conversion

### Phase 2: State Sync (4-6 hours)

1. Add voice unload callback to Pigeon API
2. Implement callback handler in Flutter
3. Clear local voice tracking on callback
4. Add periodic state refresh mechanism

### Phase 3: Progress Enhancement (Future)

1. Add sub-progress during inference
2. Add estimated time remaining
3. Implement progress UI components

---

## Test Recommendations

1. **Error Code Tests:**
   - Verify BUSY error propagates correctly
   - Verify OOM triggers LRU unload + retry
   - Verify timeout handling

2. **State Sync Tests:**
   - Simulate native memory pressure unload
   - Verify Flutter state updates

3. **Concurrent Synthesis Tests:**
   - Hit semaphore limit (5+ concurrent)
   - Verify BUSY error and retry

---

## Appendix: Current Error Code Mapping

| Native Code | Flutter Code | Correct? | Note |
|-------------|--------------|----------|------|
| `none` | `unknown` | ✅ | |
| `modelMissing` | `modelMissing` | ✅ | |
| `modelCorrupted` | `modelCorrupted` | ✅ | |
| `outOfMemory` | `inferenceFailed` | ❌ | Should be `outOfMemory` |
| `inferenceFailed` | `inferenceFailed` | ✅ | |
| `cancelled` | `cancelled` | ✅ | |
| `runtimeCrash` | `runtimeCrash` | ✅ | |
| `invalidInput` | `invalidInput` | ✅ | |
| `fileWriteError` | `fileWriteError` | ✅ | |
| `busy` | N/A | ❌ | Not in Pigeon definition |
| `unknown` | `unknown` | ✅ | |
