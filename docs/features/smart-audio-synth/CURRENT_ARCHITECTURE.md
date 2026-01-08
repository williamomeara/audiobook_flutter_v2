# Current Audio Synthesis Architecture

## Overview

This document details the **existing** audio synthesis strategy during audiobook playback. The current implementation follows a **Just-In-Time (JIT) + Background Prefetch** model.

---

## High-Level Flow

```
User Opens Chapter
    ↓
Chapter Loads → Segments Created
    ↓
Play Button Pressed
    ↓
[SYNTHESIZE CURRENT SEGMENT] ← 🔴 YOU ARE HERE (blocking)
    ↓
Audio Plays
    ↓
[Background: Prefetch Next Segments] ← 🟡 Async prefetch starts
    ↓
Audio Ends → Next Segment
    ↓
Check Cache → Play (if cached) or Synthesize (if not)
```

---

## Detailed Architecture

### **Phase 1: Chapter Loading** ✅ FAST

**File:** `lib/app/playback_providers.dart` → `loadChapter()`

**What Happens:**
1. Get chapter text from Book model
2. **Segment text** on-the-fly (using `segmentText()`)
3. Convert segments to `AudioTrack` objects
4. Load tracks into `AudiobookPlaybackController`

**Time:** ~20ms for typical chapter (instant)

**Code:**
```dart
final chapter = book.chapters[chapterIndex];
final segments = segmentText(chapter.content);  // Fast, just string splitting

final tracks = segments.map((segment) => AudioTrack(...)).toList();
await ctrl.loadChapter(tracks: tracks, ...);
```

**Key Point:** NO audio synthesis happens here. Only text processing.

---

### **Phase 2: First Segment Playback** ⏱️ BLOCKING

**File:** `packages/playback/lib/src/playback_controller.dart` → `_speakCurrent()`

**What Happens:**
1. User presses play
2. Controller calls `_speakCurrent()` for segment 0
3. **Voice readiness check** (is model downloaded?)
4. **Generate cache key** from voice + text + rate
5. **Check cache** - does file exist?
6. If NOT cached:
   - **🔴 SYNTHESIZE NOW** (blocking operation)
   - TTS inference runs (200ms - 2000ms depending on engine)
   - Write WAV file to cache
7. **Play audio** from file
8. **Start background prefetch** for upcoming segments

**Time:** 
- First play: 200ms - 2000ms (synthesis time)
- Subsequent plays: ~10ms (cache hit)

**Code Flow:**
```dart
Future<void> _speakCurrent({required int opId}) async {
  // 1. Get current track
  final track = _state.currentTrack;
  
  // 2. Voice selection
  final voiceId = voiceIdResolver(null);
  
  // 3. Check voice ready
  final voiceReadiness = await engine.checkVoiceReady(voiceId);
  
  // 4. SYNTHESIS (blocking)
  final result = await engine.synthesizeToWavFile(
    voiceId: voiceId,
    text: track.text,
    playbackRate: _state.playbackRate,
  );
  
  // 5. Play audio
  await _audioOutput.playFile(result.file.path, ...);
  
  // 6. Start background prefetch
  _startPrefetchIfNeeded();
}
```

**Cache Check Happens Inside `synthesizeToWavFile()`:**
```dart
// In RoutingEngine / Adapters
Future<SynthesisResult> synthesizeToWavFile(...) async {
  final cacheKey = CacheKeyGenerator.generate(...);
  
  // Check cache first
  if (await cache.isReady(cacheKey)) {
    return SynthesisResult(file: cacheFile, ...);  // Cache hit!
  }
  
  // Cache miss - do synthesis
  final audio = await _doActualSynthesis(text);
  await cache.store(cacheKey, audio);
  return SynthesisResult(...);
}
```

---

### **Phase 3: Background Prefetch** 🟢 NON-BLOCKING

**File:** `packages/playback/lib/src/buffer_scheduler.dart` → `runPrefetch()`

**What Happens:**
1. After first segment starts playing, prefetch begins
2. **Calculate target index** based on buffer config
3. **Loop through upcoming segments:**
   - Generate cache key
   - Check if already cached
   - If not: synthesize and store
   - Continue until target index or buffer full
4. Prefetch runs in background (doesn't block playback)

**Configuration:** (`playback_config.dart`)
```dart
static const int bufferTargetMs = 30000;      // 30 seconds target
static const int lowWatermarkMs = 10000;      // Start prefetch at 10s
static const int highWatermarkMs = 60000;     // Stop at 60s
static const int maxPrefetchTracks = 10;      // Max 10 segments ahead
```

**Prefetch Strategy:**
```dart
Future<void> runPrefetch(...) async {
  var i = _prefetchedThroughIndex + 1;
  
  while (i <= targetIndex && i < queue.length) {
    final track = queue[i];
    final cacheKey = CacheKeyGenerator.generate(...);
    
    // Skip if already cached
    if (await cache.isReady(cacheKey)) {
      _prefetchedThroughIndex = i;
      i++;
      continue;
    }
    
    // Synthesize in background
    await engine.synthesizeToWavFile(...);
    _prefetchedThroughIndex = i;
    i++;
  }
}
```

**Prefetch Triggers:**
- **When:** Buffer falls below 10 seconds
- **How much:** Synthesize until 30 seconds buffered or 10 segments
- **Stops when:** Buffer reaches 60 seconds

---

### **Phase 4: Subsequent Segments** ⚡ USUALLY CACHED

**What Happens:**
1. Current segment finishes playing
2. Controller advances to next segment
3. Calls `_speakCurrent()` again
4. Cache check:
   - **If cached:** Play immediately (fast!)
   - **If NOT cached:** Synthesize now (blocks until done)

**Cache Hit Rate:**
- **First playthrough:** 70-90% (prefetch catches most)
- **Replay same chapter:** 100% (all cached)
- **Different voice/rate:** 0% (cache is per voice+rate+text)

---

## Cache System

### **Cache Key Generation**

**File:** `packages/core_domain/lib/src/utils/cache_key_generator.dart`

**Key Components:**
```dart
CacheKey = hash(voiceId + text + synthesisRate)
```

**Rate-Independent Synthesis:**
- Always synthesizes at 1.0x speed
- Playback rate adjusted in audio player
- Maximizes cache reuse across different rates

**Example Keys:**
```
kokoro_af_bella|She walked slowly down the street.|1.0
  → produces: "a3f5e8d2c1b4a6f9.wav"

kokoro_af_bella|The morning was cold and gray.|1.0
  → produces: "7b2e4f9d8c3a1e5f.wav"
```

### **Cache Location**

**Android:** `/data/data/com.example.audiobook_flutter_v2/cache/audio_cache/`

**Structure:**
```
audio_cache/
  ├── a3f5e8d2c1b4a6f9.wav  (segment 1, voice A)
  ├── 7b2e4f9d8c3a1e5f.wav  (segment 2, voice A)
  └── ...
```

### **Cache Invalidation**

**When Cache is Cleared:**
- App data cleared by user
- OS low storage cleanup
- Manual cache clear (if implemented)

**Cache Persistence:**
- Survives app restarts
- Survives app updates
- Only cleared when explicitly deleted

---

## Current Limitations

### **❌ Problem 1: First Segment Lag**

**Issue:** User presses play → waits 500ms+ for synthesis

**Why:** No preemptive synthesis on chapter load

**User Experience:**
```
User: *taps play*
App: "Please wait while I synthesize..."  ← 🔴 BAD UX
[500-2000ms delay]
App: "Okay, here's your audio!"
```

### **❌ Problem 2: Seek/Skip Lag**

**Issue:** User seeks to segment 50 → not cached → waits again

**Why:** Prefetch only works linearly forward, doesn't predict seeks

**User Experience:**
```
User: *skips 10 segments forward*
App: "Hmm, I don't have that cached..."
[500-2000ms delay]
App: "Okay, ready now!"
```

### **❌ Problem 3: Prefetch Gaps**

**Issue:** If user pauses for a long time, prefetch stops

**Why:** Prefetch only runs during active playback

**User Experience:**
```
User: *pauses for 5 minutes*
User: *resumes at segment 5*
App: "I stopped prefetching, synthesizing now..."
[delay again]
```

### **❌ Problem 4: Chapter Switch Lag**

**Issue:** Moving to next chapter → ALL segments uncached

**Why:** No cross-chapter prefetch

**User Experience:**
```
User: *finishes chapter 1*
User: *auto-advance to chapter 2*
App: "New chapter, synthesizing..."  ← 🔴 INTERRUPTION
[delay]
```

---

## Performance Metrics

### **Synthesis Times** (measured on mid-range Android device)

**Kokoro:**
- Short segment (10 words): ~200ms
- Medium segment (20 words): ~400ms
- Long segment (40 words): ~800ms

**Piper:**
- Short: ~100ms
- Medium: ~200ms
- Long: ~400ms

**Supertonic:**
- Short: ~300ms
- Medium: ~600ms
- Long: ~1200ms

### **Buffer Calculations**

**Example Chapter:**
- 50 segments @ 20 words each
- ~400ms synthesis each
- Total synthesis time: 20 seconds (if sequential)

**With Current Prefetch:**
- First segment: 400ms wait (blocks)
- Next 9 segments: prefetched while segment 1 plays
- Smooth from segment 2-10
- Prefetch continues as needed

**Buffer Depth:**
```
10 seconds buffer = ~7-10 segments (depending on text length)
30 seconds buffer = ~20-25 segments
```

---

## Code Locations

### **Key Files:**

1. **Playback Control:**
   - `packages/playback/lib/src/playback_controller.dart` (main controller)
   - `packages/playback/lib/src/buffer_scheduler.dart` (prefetch logic)
   - `packages/playback/lib/src/playback_config.dart` (tuning constants)

2. **TTS Synthesis:**
   - `packages/tts_engines/lib/src/routing_engine.dart` (engine router)
   - `packages/tts_engines/lib/src/adapters/kokoro_adapter.dart` (Kokoro impl)
   - `packages/tts_engines/lib/src/synthesis_pool.dart` (parallel synthesis)

3. **Caching:**
   - `packages/tts_engines/lib/src/cache/audio_cache.dart` (cache interface)
   - `packages/core_domain/lib/src/utils/cache_key_generator.dart` (key generation)

4. **App Integration:**
   - `lib/app/playback_providers.dart` (Riverpod providers)
   - `lib/ui/screens/playback_screen.dart` (UI)

---

## Summary: Current Strategy

### **What Works Well ✅**

1. **Simple and reliable** - straightforward logic
2. **Cache reuse** - rate-independent synthesis
3. **Background prefetch** - smooth playback after first segment
4. **Memory efficient** - only buffers ahead, not entire chapter

### **What Needs Improvement ❌**

1. **First segment lag** - blocking synthesis on play
2. **Seek lag** - no intelligent prefetch prediction
3. **Chapter boundaries** - no cross-chapter prefetch
4. **Pause/resume gaps** - prefetch stops when paused

---

## Next Steps: Smart Audio Synthesis

The new "smart-audio-synth-in-playback" branch will address these issues with:

1. **Preemptive synthesis** on chapter load
2. **Intelligent prefetch** predicting user behavior
3. **Cross-chapter buffering** for seamless transitions
4. **Persistent prefetch** during pause/background

See `PROPOSED_IMPROVEMENTS.md` for the new architecture design.
