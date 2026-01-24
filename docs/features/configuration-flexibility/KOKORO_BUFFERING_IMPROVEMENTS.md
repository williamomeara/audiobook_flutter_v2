# Kokoro Buffering Improvements Analysis

**Date:** 2026-01-24  
**Status:** Proposed  
**Related:** Configuration Flexibility Implementation (Phases 1-3)

## Problem Summary

Kokoro TTS synthesis is **2.5-3x slower than real-time** on the test device (OnePlus CPH2695). Combined with 2.0x playback speed, synthesis can never keep pace with playback, resulting in:
- Prefetch constantly aborting with "Context changed"
- Buffer always showing 0.0s
- User experiences gaps between segments

### Log Evidence

| Segment | Synthesis Time | Audio Duration | Ratio |
|---------|---------------|----------------|-------|
| [3]     | 27,337ms      | 9,675ms        | **2.8x slower** |
| [4]     | 35,503ms      | 13,514ms       | **2.6x slower** |
| [5]     | 11,975ms      | 4,821ms        | **2.5x slower** |
| [9]     | 28,261ms      | 9,426ms        | **3.0x slower** |
| [12]    | 27,019ms      | 9,889ms        | **2.7x slower** |

At 2.0x playback, a 10-second audio clip plays in 5 seconds, but synthesis takes 25-30 seconds.

## Proposed Improvements

### 1. Pause-Based Pre-Synthesis (High Impact)

**Current Behavior:** When track N completes, if track N+1 isn't ready, user hears silence while synthesis runs.

**Proposed:** Auto-pause playback with visual indicator showing synthesis progress.

```dart
// In playback_controller.dart, during track transition
if (!isNextTrackReady) {
  await pause();
  _updateState(state.copyWith(
    isBuffering: true,
    bufferingMessage: 'Synthesizing next segment...',
  ));
  // Wait for synthesis to complete
  await waitForTrackReady(nextIndex);
  await play(); // Resume automatically
}
```

**Pros:** No silent gaps, user knows what's happening  
**Cons:** Playback not continuous, requires UI indicator

---

### 2. Parallel Prefetch for Kokoro (Medium Impact)

**Current:** `kokoroConcurrency = 1` (sequential synthesis)  
**Proposed:** Enable `kokoroConcurrency = 2` on devices with sufficient RAM

```dart
// In playback_config.dart
static int get kokoroConcurrency {
  // Could be dynamic based on device RAM
  return DeviceInfo.totalRam > 4000 ? 2 : 1;
}
```

**Pros:** Could cut effective RTF in half  
**Cons:** Higher memory usage, risk of OOM on budget devices, ONNX Runtime may not parallelize efficiently

---

### 3. RTF-Aware Playback Speed Warning (Low Risk, Quick Win) ⭐

**Current:** Adaptive prefetch has RTF awareness but doesn't warn user  
**Proposed:** Show warning when `RTF * playbackRate > 0.9`

```dart
// In playback_providers.dart or settings_screen.dart
void checkPlaybackRateViability(double rtf, double playbackRate, String voiceName) {
  final effectiveRatio = rtf * playbackRate;
  if (effectiveRatio > 0.9) {
    showSnackBar(
      'With $voiceName at ${playbackRate}x speed, synthesis may not keep up. '
      'Consider reducing speed to ${(0.8 / rtf).toStringAsFixed(1)}x or using Piper.',
    );
  }
}
```

**Pros:** User understands the tradeoff, can make informed choice  
**Cons:** Just a warning, doesn't fix underlying issue

---

### 4. Larger Segments (Reduce TTS Overhead) (Medium Impact)

**Current:** Sentence-based segmentation (~10-50 words per segment)  
**Proposed:** Configurable segment size, defaulting to 2-3 sentences for Kokoro

```dart
// In text_segmenter.dart or playback_config.dart
static int getTargetWordsPerSegment(String engineType) {
  return switch (engineType) {
    'kokoro' => 100,  // 2-3 sentences, ~25s audio
    'piper' => 40,    // Keep smaller for fast engine
    'supertonic' => 60,
    _ => 50,
  };
}
```

**Pros:** Fewer synthesis calls, less overhead  
**Cons:** Longer initial wait, less granular seeking

---

### 5. Smarter Track Transition with ETA (Low Risk, Quick Win) ⭐

**Current:** "Buffering" with no progress indication  
**Proposed:** Show estimated time based on measured RTF

```dart
// During synthesis, display:
// "Synthesizing (est. 15s remaining)"

String getBufferingMessage(int wordCount, double measuredRTF) {
  // Estimate: ~100 words = ~7s audio → ~20s synthesis at 2.8x RTF
  final estimatedAudioSecs = wordCount * 0.07;  // ~7s per 100 words
  final estimatedSynthSecs = estimatedAudioSecs * measuredRTF;
  return 'Synthesizing (${estimatedSynthSecs.round()}s)...';
}
```

**Pros:** Better UX, sets user expectations  
**Cons:** Estimate may be inaccurate

---

### 6. Background Synthesis During Idle (Long-term)

**Current:** Prefetch only runs during active playback  
**Proposed:** When app is open but paused, aggressively pre-synthesize chapter

```dart
// Trigger when:
// - Playback is paused for > 5 seconds
// - Battery > 30%
// - Device not in power saver mode

void onIdleDetected() {
  if (canBackgroundSynthesize()) {
    synthesizeRemainingChapter(startIndex: currentTrackIndex + 1);
  }
}
```

**Pros:** Proactive caching, smooth playback when resumed  
**Cons:** Battery usage when user may not resume, complex state management

---

## Recommended Implementation Order

1. **Phase 1 (Quick wins):**
   - #3: RTF-aware playback speed warning
   - #5: Better buffering message with ETA

2. **Phase 2 (Medium effort):**
   - #1: Pause-based transition (requires UI changes)
   - #4: Configurable segment size

3. **Phase 3 (Research needed):**
   - #2: Parallel synthesis (needs device testing)
   - #6: Background synthesis (needs power profiling)

---

## What's Working Correctly

The logs confirm these systems are functioning properly:
- ✅ Engine memory management (Kokoro stays loaded, no reload overhead)
- ✅ Audio playback at 2.0x speed
- ✅ Cache hit logic (when segments are cached, they play instantly)
- ✅ Progress tracking (25%, 50%, 75%)
- ✅ Prefetch target calculation (correctly identifies 14-15 segments ahead)
- ✅ Context change detection (prevents stale prefetch from blocking)

---

## Alternative: Engine Recommendations

For users who want smooth playback:
- **Piper:** ~0.3x RTF, can keep up with 3.0x playback speed
- **Supertonic:** ~0.5x RTF, good balance of quality and speed

Could add settings screen guidance:
```
Kokoro (High Quality): Best for battery-powered listening at 1.0-1.5x
Piper (Fast): Best for speed listeners (2.0x+)
Supertonic (Balanced): Good quality at moderate speeds
```
