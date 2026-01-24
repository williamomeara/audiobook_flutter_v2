# Android TTS Implementation Improvements

## Overview

Based on learnings from the iOS implementation, here are improvements that could be applied to the Android TTS system to enhance performance, reliability, and memory management.

## High Priority Improvements

### 1. Fix Double Synthesis Calls (Kokoro & Piper)

**Issue:** Both Kokoro and Piper engines synthesize audio twice - once to get duration/samples, then again to write the file.

**Current Code Pattern (KokoroTtsService.kt):**
```kotlin
// First synthesis - line ~163
val samples = engine.synthesize(text, actualSpeakerId, speed).getOrThrow()

// ... later at line ~198
val samples = engine.synthesize(text, actualSpeakerId, speed).getOrNull()  // REDUNDANT!
```

**Impact:** 
- 2x GPU/CPU computation overhead
- Doubles synthesis time per request
- Wastes battery on mobile devices

**Fix:** Synthesize once and reuse the samples array for both duration calculation and file writing.

```kotlin
val samples = engine.synthesize(text, actualSpeakerId, speed).getOrThrow()
writeWavFile(tmpFile, samples, sampleRate)
val durationMs = (samples.size * 1000 / sampleRate)
```

**Files to modify:**
- `packages/platform_android_tts/android/src/main/kotlin/.../services/KokoroTtsService.kt`
- `packages/platform_android_tts/android/src/main/kotlin/.../services/PiperTtsService.kt`

---

### 2. Add Synthesis Counter Pattern

**Issue:** Android services don't track active synthesis operations, risking model unload during synthesis.

**iOS Pattern:** Uses `SynthesisCounter` + locks to prevent unload during active work:
```swift
class SupertonicTtsService {
    private let synthesisCounter = SynthesisCounter()
    
    func synthesize(...) {
        synthesisCounter.increment()
        defer { synthesisCounter.decrement() }
        // ... synthesis logic
    }
    
    func unloadVoice(...) {
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        // ... unload logic
    }
}
```

**Android Implementation:**
```kotlin
class SynthesisCounter {
    private val count = AtomicInteger(0)
    
    fun increment() = count.incrementAndGet()
    fun decrement() = count.decrementAndGet()
    fun isIdle(): Boolean = count.get() == 0
    
    fun waitUntilIdle(timeoutMs: Long): Boolean {
        val startTime = System.currentTimeMillis()
        while (!isIdle()) {
            if (System.currentTimeMillis() - startTime > timeoutMs) return false
            Thread.sleep(100)
        }
        return true
    }
}
```

**Files to modify:**
- `packages/platform_android_tts/android/src/main/kotlin/.../services/KokoroTtsService.kt`
- `packages/platform_android_tts/android/src/main/kotlin/.../services/PiperTtsService.kt`
- `packages/platform_android_tts/android/src/main/kotlin/.../services/SupertonicTtsService.kt`

---

### 3. Memory Pressure Monitoring

**Issue:** No proactive memory management - OOM errors only handled reactively.

**Recommendation:** Add memory threshold checks before loading new models:

```kotlin
object MemoryManager {
    private const val MAX_MODEL_MEMORY_MB = 500
    
    fun checkMemoryPressure(context: Context): Boolean {
        val runtime = Runtime.getRuntime()
        val usedMB = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
        return usedMB > MAX_MODEL_MEMORY_MB
    }
    
    fun getRecommendedAction(): MemoryAction {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        
        return when {
            memoryInfo.lowMemory -> MemoryAction.UNLOAD_ALL
            memoryInfo.availMem < 100 * 1024 * 1024 -> MemoryAction.UNLOAD_LRU
            else -> MemoryAction.NONE
        }
    }
}
```

---

## Medium Priority Improvements

### 4. Track Request Ownership for Cancellation

**Issue:** `cancelSynthesis()` broadcasts to all 3 engine services even if only one owns the request.

**Current Code:**
```kotlin
override fun cancelSynthesis(requestId: String, callback: ...) {
    kokoroService.cancelSynthesis(requestId)    // May not own it
    piperService.cancelSynthesis(requestId)     // May not own it  
    supertonicService.cancelSynthesis(requestId) // May not own it
    callback(Result.success(Unit))
}
```

**Fix:** Track which engine started each request:
```kotlin
private val requestOwners = ConcurrentHashMap<String, NativeEngineType>()

override fun synthesize(request: SynthesizeRequest, callback: ...) {
    requestOwners[request.requestId] = request.engineType
    // ... synthesis logic
}

override fun cancelSynthesis(requestId: String, callback: ...) {
    when (requestOwners.remove(requestId)) {
        NativeEngineType.KOKORO -> kokoroService.cancelSynthesis(requestId)
        NativeEngineType.PIPER -> piperService.cancelSynthesis(requestId)
        NativeEngineType.SUPERTONIC -> supertonicService.cancelSynthesis(requestId)
        null -> {} // Already completed or unknown
    }
    callback(Result.success(Unit))
}
```

---

### 5. Centralize Path Logic

**Issue:** Path construction is duplicated across adapters with hardcoded patterns.

**Current Pattern:**
```dart
// KokoroAdapter
final coreDir = Directory('${_coreDir.path}/kokoro/kokoro_core_v1');

// SupertonicAdapter (with platform checks)
final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
```

**Recommended:** Create a centralized `CorePaths` utility:
```dart
class CorePaths {
  final Directory baseDir;
  
  CorePaths(this.baseDir);
  
  Directory getCoreDirectory(String engineType, String coreId) {
    return Directory('${baseDir.path}/$engineType/$coreId');
  }
  
  String getModelPath(String engineType, String coreId) {
    final coreDir = getCoreDirectory(engineType, coreId);
    return switch (engineType) {
      'kokoro' => coreDir.path,
      'piper' => coreDir.path,
      'supertonic' => Platform.isIOS 
          ? '${coreDir.path}/supertonic_coreml'
          : '${coreDir.path}/supertonic/onnx/model.onnx',
      _ => throw ArgumentError('Unknown engine: $engineType'),
    };
  }
}
```

---

### 6. Add Temp File Cleanup on Startup

**Issue:** Orphaned `.tmp` files from interrupted downloads accumulate.

**Recommendation:** Clean up on app startup:
```dart
// In GranularDownloadManager.build()
Future<void> _cleanupOrphanedTempFiles() async {
  final entities = await _baseDir.list(recursive: true).toList();
  for (final entity in entities) {
    if (entity is File && entity.path.endsWith('.tmp')) {
      try {
        final stat = await entity.stat();
        // Delete if older than 1 hour
        if (DateTime.now().difference(stat.modified).inHours > 1) {
          await entity.delete();
          debugPrint('[Cleanup] Deleted orphaned temp file: ${entity.path}');
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }
}
```

---

## Low Priority Improvements

### 7. Model Loading Efficiency (Piper)

**Issue:** Piper checks `loadedVoices` but may re-initialize `PiperSherpaInference` on each synthesis.

**Recommendation:** Cache inference engines more aggressively and implement LRU eviction.

### 8. Error Context Enhancement

**Issue:** Generic error messages don't help debugging.

**Recommendation:** Add more context to exceptions:
```kotlin
throw TtsException(
    errorCode = TtsErrorCode.MODEL_LOAD_FAILED,
    message = "Failed to load Kokoro model",
    cause = e,
    context = mapOf(
        "modelPath" to modelPath,
        "availableMemoryMB" to availableMemoryMB,
        "voiceId" to voiceId
    )
)
```

---

## Implementation Priority

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 🔴 High | Fix double synthesis | Low | High |
| 🔴 High | Add synthesis counter | Medium | High |
| 🟡 Medium | Memory pressure monitoring | Medium | Medium |
| 🟡 Medium | Request ownership tracking | Low | Medium |
| 🟡 Medium | Centralize path logic | Medium | Medium |
| 🟢 Low | Temp file cleanup | Low | Low |
| 🟢 Low | Model loading optimization | High | Medium |
| 🟢 Low | Error context enhancement | Low | Low |

---

## Related Files

### Dart (Flutter)
- `lib/app/granular_download_manager.dart` - Download logic
- `packages/tts_engines/lib/src/adapters/kokoro_adapter.dart`
- `packages/tts_engines/lib/src/adapters/piper_adapter.dart`
- `packages/tts_engines/lib/src/adapters/supertonic_adapter.dart`

### Android (Kotlin)
- `packages/platform_android_tts/android/src/main/kotlin/.../TtsNativeApiImpl.kt`
- `packages/platform_android_tts/android/src/main/kotlin/.../services/KokoroTtsService.kt`
- `packages/platform_android_tts/android/src/main/kotlin/.../services/PiperTtsService.kt`
- `packages/platform_android_tts/android/src/main/kotlin/.../services/SupertonicTtsService.kt`

### iOS (Swift) - Reference patterns
- `packages/platform_ios_tts/ios/Classes/engines/SupertonicTtsService.swift` - SynthesisCounter pattern
- `packages/platform_ios_tts/ios/Classes/common/SynthesisCounter.swift`
