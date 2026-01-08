# Comprehensive Playback Logging Implementation

## Overview

Extensive logging has been added throughout the playback system to track every aspect of audio synthesis, caching, and playback during audiobook reading.

---

## What's Been Logged

### **1. Audio Output Layer** (`packages/playback/lib/src/audio_output.dart`)

#### **Initialization:**
```
[AudioOutput] Initializing JustAudioOutput
[AudioOutput] Setting up event listeners
[AudioOutput] Audio session configured for speech playback
```

#### **File Playback:**
```
[AudioOutput] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[AudioOutput] PLAY FILE REQUEST
[AudioOutput] Path: /path/to/audio.wav
[AudioOutput] Playback Rate: 1.0x
[AudioOutput] ✓ File exists: 15.23KB
[AudioOutput] Setting audio source...
[AudioOutput] ✓ Source set, duration: 3500ms (3s)
[AudioOutput] ✓ Speed set to: 1.0x
[AudioOutput] Player state before play: playing=false, processingState=ready
[AudioOutput] ▶ Calling play()...
[AudioOutput] play() returned, playing=true, processingState=ready
[AudioOutput] After 100ms: playing=true, processingState=ready
[AudioOutput] Volume: 1.0
[AudioOutput] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### **State Changes:**
```
[AudioOutput] Player state changed: loading, playing: false
[AudioOutput] ↳ Loading audio...
[AudioOutput] Player state changed: ready, playing: false
[AudioOutput] ↳ Ready to play
[AudioOutput] Player state changed: ready, playing: true
[AudioOutput] ↳ Playback started
[AudioOutput] Player state changed: completed, playing: false
[AudioOutput] ↳ Track completed
```

#### **Progress Tracking:**
```
[AudioOutput] Playback progress: 25.0% (0s / 3s)
[AudioOutput] Playback progress: 50.0% (1s / 3s)
[AudioOutput] Playback progress: 75.0% (2s / 3s)
```

#### **Controls:**
```
[AudioOutput] ⏸ PAUSE requested
[AudioOutput] ⏸ Paused at position: 0:01:23.450
[AudioOutput] 🏃 Setting speed to 1.5x
[AudioOutput] 🏃 Speed updated
[AudioOutput] ⏹ STOP requested
[AudioOutput] ⏹ Stopped and cancelled
```

---

### **2. Buffer Scheduler** (`packages/playback/lib/src/buffer_scheduler.dart`)

#### **Buffer Checks:**
```
[BufferScheduler] Buffer check: 8.5s buffered (threshold: 10.0s) → START PREFETCH
[BufferScheduler] Calculating target index from current=5
[BufferScheduler] Target reached at index 15 (30.2s buffered)
[BufferScheduler] Target index: 15 (10 segments ahead)
```

#### **Prefetch Session:**
```
[BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━
[BufferScheduler] PREFETCH START
[BufferScheduler] Target index: 15
[BufferScheduler] Current prefetched through: 5
[BufferScheduler] Voice: kokoro_af_bella, Rate: 1.0x
[BufferScheduler] Starting from index 6

[BufferScheduler] [6/50] Prefetching: "She walked slowly down the street..." (8 words)
[BufferScheduler] ✓ [6] Already cached: a3f5e8d2c1b4a6f9

[BufferScheduler] [7/50] Prefetching: "The morning was cold and gray..." (6 words)
[BufferScheduler] 🔄 [7] Synthesizing (not in cache)...
[BufferScheduler] ✓ [7] Synthesized in 412ms

[BufferScheduler] [8/50] Prefetching: "Detective Sarah Chen stood at the..." (17 words)
[BufferScheduler] 🔄 [8] Synthesizing (not in cache)...
[BufferScheduler] ✓ [8] Synthesized in 523ms

... (continues for all segments)

[BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━
[BufferScheduler] PREFETCH COMPLETE
[BufferScheduler] Total time: 4523ms
[BufferScheduler] Synthesized: 8, Cached: 2, Failed: 0
[BufferScheduler] Final prefetched index: 15
[BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### **Errors:**
```
[BufferScheduler] ❌ [12] Synthesis failed after 234ms: Voice model not loaded
[BufferScheduler] Stack trace: (full stack trace)
```

---

### **3. Playback Controller** (`packages/playback/lib/src/playback_controller.dart`)

Already has comprehensive logging from previous session:

```
[AudiobookPlaybackController] Loading chapter with 312 tracks (start: 0, autoPlay: false)
[AudiobookPlaybackController] State updated with 312 tracks in queue
[AudiobookPlaybackController] Auto-play disabled, chapter loaded and ready
[AudiobookPlaybackController] Speaking track 0: "The morning was cold and gray..."
[AudiobookPlaybackController] Using voice: kokoro_af_bella
[AudiobookPlaybackController] Checking voice readiness...
[AudiobookPlaybackController] Voice is ready, starting synthesis...
[AudiobookPlaybackController] Synthesis complete in 412ms
[AudiobookPlaybackController] Audio file: /data/.../a3f5e8d2c1b4a6f9.wav
[AudiobookPlaybackController] Duration: 3500ms
[AudiobookPlaybackController] Starting audio playback...
[AudiobookPlaybackController] Audio playback started successfully
```

---

### **4. Playback Providers** (`lib/app/playback_providers.dart`)

Already has logging from previous session:

```
[PlaybackProvider] Initializing playback controller...
[PlaybackProvider] Loading routing engine...
[PlaybackProvider] Routing engine loaded successfully
[PlaybackProvider] Loading audio cache...
[PlaybackProvider] Audio cache loaded successfully
[PlaybackProvider] Creating AudiobookPlaybackController...
[PlaybackProvider] Controller created successfully
[PlaybackProvider] Initialization complete

[PlaybackProvider] Loading chapter 0 for book "1984"
[PlaybackProvider] Chapter: "Part One", content length: 45231 chars
[PlaybackProvider] Segmented into 312 segments in 23ms
[PlaybackProvider] Converting 312 segments to AudioTracks...
[PlaybackProvider] Loading 312 tracks into controller (starting at index 0)
[PlaybackProvider] Chapter loaded successfully
```

---

## Log Flow Example: First Play

**Complete sequence when user presses play on a chapter:**

```
1. [PlaybackScreen] Calling loadChapter...
2. [PlaybackProvider] Loading chapter 0 for book "1984"
3. [PlaybackProvider] Segmented into 312 segments in 23ms
4. [AudiobookPlaybackController] Loading chapter with 312 tracks
5. [AudiobookPlaybackController] State updated with 312 tracks in queue

--- User presses play ---

6. [AudiobookPlaybackController] Speaking track 0: "The morning..."
7. [AudiobookPlaybackController] Using voice: kokoro_af_bella
8. [AudiobookPlaybackController] Voice is ready, starting synthesis...
9. [AudiobookPlaybackController] Synthesis complete in 412ms
10. [AudiobookPlaybackController] Audio file: ...a3f5e8d2c1b4a6f9.wav
11. [AudioOutput] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
12. [AudioOutput] PLAY FILE REQUEST
13. [AudioOutput] Path: /data/.../a3f5e8d2c1b4a6f9.wav
14. [AudioOutput] ✓ File exists: 15.23KB
15. [AudioOutput] ✓ Source set, duration: 3500ms
16. [AudioOutput] ✓ Speed set to: 1.0x
17. [AudioOutput] ▶ Calling play()...
18. [AudioOutput] Player state changed: ready, playing: true
19. [AudioOutput] ↳ Playback started
20. [AudioOutput] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--- Background prefetch starts ---

21. [BufferScheduler] Buffer check: 0.0s buffered → START PREFETCH
22. [BufferScheduler] Calculating target index from current=0
23. [BufferScheduler] Target index: 10 (10 segments ahead)
24. [BufferScheduler] ━━━━━━━━━━━━━━━━━━━━━━━━━━━
25. [BufferScheduler] PREFETCH START
26. [BufferScheduler] [1/312] Prefetching: "Detective Sarah Chen..."
27. [BufferScheduler] 🔄 [1] Synthesizing (not in cache)...
28. [BufferScheduler] ✓ [1] Synthesized in 523ms
... (continues for segments 2-10)

--- Audio finishes ---

29. [AudioOutput] Playback progress: 75.0%
30. [AudioOutput] Player state changed: completed
31. [AudioOutput] ↳ Track completed
32. [AudiobookPlaybackController] Speaking track 1: "Detective Sarah..."
33. [AudioOutput] PLAY FILE REQUEST (cached)
... (cycle repeats)
```

---

## Log Symbols Used

- ✓ Success / Complete
- ❌ Error / Failed
- ⚠ Warning / Attention needed
- 🔄 In progress / Working
- ▶ Play started
- ⏸ Paused
- ⏹ Stopped
- 🏃 Speed/Rate change
- 🗑 Disposal/Cleanup
- ━━━ Section separator

---

## Filtering Logs

### **To see only synthesis events:**
```bash
adb logcat | grep "Synthesiz"
```

### **To see only prefetch:**
```bash
adb logcat | grep "BufferScheduler"
```

### **To see only playback:**
```bash
adb logcat | grep "AudioOutput"
```

### **To see everything:**
```bash
flutter run --verbose
# or
adb logcat | grep -E "(AudioOutput|BufferScheduler|PlaybackController|PlaybackProvider)"
```

---

## Performance Insights from Logs

### **What You Can Track:**

1. **Synthesis Times:**
   - How long each segment takes to synthesize
   - Cache hit rate (already cached vs synthesized)

2. **Buffer Health:**
   - How much audio is buffered ahead
   - When prefetch triggers
   - How many segments prefetched

3. **Playback Smoothness:**
   - Gaps between tracks
   - State transitions
   - Progress through segments

4. **Error Patterns:**
   - Which segments fail synthesis
   - Why they fail
   - Recovery behavior

---

## What to Look For

### **❌ Red Flags:**

1. **Long synthesis times:**
   ```
   [BufferScheduler] ✓ [12] Synthesized in 2500ms  ← TOO SLOW!
   ```

2. **Cache misses on replay:**
   ```
   [BufferScheduler] 🔄 [5] Synthesizing (not in cache)...  ← Should be cached!
   ```

3. **Buffer starvation:**
   ```
   [BufferScheduler] Buffer check: 0.5s buffered  ← TOO LOW!
   ```

4. **Frequent prefetch failures:**
   ```
   [BufferScheduler] Failed: 8  ← INVESTIGATE!
   ```

### **✅ Good Signs:**

1. **Fast synthesis:**
   ```
   [BufferScheduler] ✓ [7] Synthesized in 412ms  ← GOOD!
   ```

2. **High cache hit rate:**
   ```
   [BufferScheduler] Synthesized: 2, Cached: 8  ← 80% cached!
   ```

3. **Healthy buffer:**
   ```
   [BufferScheduler] Buffer check: 28.5s buffered  ← PLENTY!
   ```

4. **Smooth playback:**
   ```
   [AudioOutput] Player state changed: completed
   [AudiobookPlaybackController] Speaking track 1...  ← Immediate!
   ```

---

## Next Steps

With this comprehensive logging in place, you can now:

1. **Run the app** and observe the complete playback flow
2. **Identify bottlenecks** in synthesis or caching
3. **Understand buffer behavior** during different usage patterns
4. **Design improvements** based on actual performance data

See logs in real-time with:
```bash
flutter run && adb logcat | grep -E "(Audio|Buffer|Playback)"
```
