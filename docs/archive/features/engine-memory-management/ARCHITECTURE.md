# TTS Engine Memory Management Architecture

## Problem
- Multiple TTS engines (Kokoro, Piper, Supertonic, + future)
- Each loads large neural network models (50-500MB each)
- iOS memory limit: ~3GB, often reached when multiple engines loaded
- CoreML and ONNX Runtime compete for GPU memory

## Current Behavior
- All engines can be loaded simultaneously
- No automatic cleanup when switching engines
- Memory accumulates until crash

## Proposed Solution: Active Engine Manager

### Core Concept
Users typically use **one voice at a time**. When switching voices across engines, unload the previous engine to free memory.

### Architecture

```
┌─────────────────────────────────────────────────┐
│              RoutingEngine                       │
│  ┌─────────────────────────────────────────┐    │
│  │         EngineMemoryManager             │    │
│  │  - activeEngine: EngineType?            │    │
│  │  - unloadInactive()                     │    │
│  │  - switchEngine(newEngine)              │    │
│  └─────────────────────────────────────────┘    │
│                     │                           │
│  ┌──────────────────┼──────────────────────┐    │
│  │      │           │           │          │    │
│  ▼      ▼           ▼           ▼          ▼    │
│ Kokoro Piper   Supertonic   Future1   Future2   │
└─────────────────────────────────────────────────┘
```

### Implementation Strategy

#### Option A: Aggressive (iOS default)
- Only ONE engine loaded at a time
- Switch engine = unload previous completely
- Pro: Maximum memory savings
- Con: Slower voice switching between engines

#### Option B: Lazy (Android default)
- Keep last 2 engines in memory
- LRU eviction when third is loaded
- Pro: Faster switching between recent engines
- Con: Uses more memory

#### Option C: Hybrid (Recommended)
- Platform-aware defaults (aggressive on iOS, lazy on Android)
- User configurable via settings
- Memory pressure detection triggers cleanup

### Implementation Steps

1. **Add EngineMemoryManager to RoutingEngine**
   ```dart
   class EngineMemoryManager {
     EngineType? _activeEngine;
     final int maxLoadedEngines;  // 1 for iOS, 2 for Android
     
     Future<void> prepareForEngine(EngineType engine, {
       required Future<void> Function(EngineType) unloader,
     }) async {
       if (_activeEngine != null && _activeEngine != engine) {
         await unloader(_activeEngine!);
       }
       _activeEngine = engine;
     }
   }
   ```

2. **Modify RoutingEngine._engineForVoice()**
   - Before returning engine, call `memoryManager.prepareForEngine()`
   - Unload inactive engines

3. **Add clearAllModels() to each adapter**
   - Already exists in interface
   - Ensure it fully releases native resources

4. **iOS Native: Add explicit cleanup**
   - Release CoreML model references
   - Force garbage collection if needed

### Native Layer Improvements

#### iOS
```swift
protocol TtsEngineProtocol {
    func loadCore(...) async throws
    func loadVoice(...) async throws
    func synthesize(...) async throws -> SynthesizeResult
    func unloadVoice(voiceId: String)
    func unloadAll()  // <-- Critical for memory management
}
```

#### Unload Priority
1. Unload voices (smaller memory footprint)
2. Unload cores (larger, but may be shared)
3. Full engine dispose (complete cleanup)

### Settings UI

Add to Settings screen:
```
Memory Management:
  [ ] Keep only active engine (saves memory)
  [ ] Keep recent engines (faster switching)
```

### Metrics to Track
- Peak memory usage per engine combination
- Time to switch between engines
- Memory freed on unload

### Future Proofing
- Each new engine just needs to implement `AiVoiceEngine` interface
- Memory manager handles cleanup automatically
- No changes needed to existing engines when adding new ones

## Implementation Checklist

- [x] Add `EngineMemoryManager` class (`packages/tts_engines/lib/src/interfaces/engine_memory_manager.dart`)
- [x] Integrate with `RoutingEngine` (uses `_prepareEngineForVoice` before synthesis)
- [x] Update iOS adapters with proper `unloadAll()` (already implemented)
- [ ] Test engine switching on iOS (Supertonic → Piper → Kokoro)
- [x] Add memory usage logging (TtsLog used in EngineMemoryManager)
- [ ] Optional: Settings UI for memory mode

## Implementation Notes (2026-01-06)

**Files Created/Modified:**
- Created: `packages/tts_engines/lib/src/interfaces/engine_memory_manager.dart`
- Modified: `packages/tts_engines/lib/src/adapters/routing_engine.dart`
- Modified: `packages/tts_engines/lib/tts_engines.dart` (export)

**Key Design Decisions:**
- Platform-aware defaults: 1 engine on iOS, 2 on Android
- LRU eviction: oldest engine unloaded first
- Async unload callbacks to handle cleanup properly
- Uses existing `clearAllModels()` → `unloadEngine()` → `unloadAll()` chain
