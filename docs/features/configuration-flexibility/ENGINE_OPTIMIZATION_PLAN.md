# Engine Optimization: Auto-Tuning and User Controls Plan

**Date:** 2026-01-24  
**Status:** Proposed  
**Related:** Phase 4 Parallel Synthesis, Configuration Flexibility

## Background

The auto-tune benchmark on OPPO A5 Pro showed significant speedups with parallel synthesis:
- **Concurrency 1:** 117.9s baseline
- **Concurrency 2:** 79.9s (1.48x speedup)
- **Concurrency 3:** 71.4s (1.65x speedup, no failures!)

This demonstrates that enabling parallel synthesis can dramatically reduce buffering for users.

## Two Approaches

### Option A: Fully Automatic (Recommended) ⭐

Users press one button, app optimizes everything automatically.

**Pros:**
- Zero cognitive load for users
- Works for 99% of users
- Can include more sophisticated optimizations (memory monitoring, battery-aware)

**Cons:**
- Less control for power users
- Initial benchmark takes ~5 minutes

### Option B: User Settings + Auto-Suggestion

Expose settings with auto-detected recommendations.

**Pros:**
- Power users can fine-tune
- Transparent about what settings exist

**Cons:**
- Most users won't understand the settings
- Risk of users breaking their experience

---

## Recommended Solution: Hybrid Approach

**Automatic optimization by default, with optional advanced settings for power users.**

### Phase 1: Smart Defaults (Immediate)

Enable parallel synthesis with safe defaults:
```dart
// In PlaybackConfig
static const bool parallelSynthesisEnabled = true;  // Enable by default
static const int kokoroConcurrency = 2;             // Conservative default
static const int supertonicConcurrency = 2;
static const int piperConcurrency = 2;
```

### Phase 2: First-Run Engine Calibration (1 week)

When user first uses a TTS engine, run a quick calibration:

```dart
class EngineCalibrationService {
  /// Run quick calibration on first use of an engine.
  /// Takes ~30 seconds, tests 3 segments at each concurrency level.
  Future<CalibrationResult> calibrateEngine(String engineType, String voiceId) async {
    // 1. Test concurrency 1, 2, 3 with 3 short segments each
    // 2. Measure time and check for failures
    // 3. Store optimal concurrency in RuntimePlaybackConfig
    // 4. Show brief result to user
  }
}

class CalibrationResult {
  final int optimalConcurrency;
  final double expectedSpeedup;
  final bool hasWarnings;
}
```

**UI Flow:**
1. User selects Kokoro voice for first time
2. Dialog: "Optimizing Kokoro for your device... (30 seconds)"
3. Brief progress indicator
4. Result: "✓ Kokoro optimized! 1.6x faster synthesis."

### Phase 3: Settings Page Enhancement (1-2 weeks)

Add an "Audio Performance" section to Settings:

```
Settings > Audio Performance

┌─────────────────────────────────────────┐
│ 🔧 Engine Optimization                   │
│ ────────────────────────────────────    │
│ Kokoro:     Optimized ✓ (1.6x)         │
│ Piper:      Not calibrated   [Optimize] │
│ Supertonic: Optimized ✓ (1.3x)         │
│                                          │
│           [Re-calibrate All]             │
└─────────────────────────────────────────┘

Advanced Settings (collapsed by default)
┌─────────────────────────────────────────┐
│ ⚙️ Advanced (for power users)            │
│ ────────────────────────────────────    │
│ Parallel Synthesis:  [ON / OFF]         │
│ Kokoro Concurrency:  [1] [2] [3] [4]    │
│ Piper Concurrency:   [1] [2] [3] [4]    │
│ Supertonic Concurrency: [1] [2] [3] [4] │
│                                          │
│ Memory Threshold:    200 MB (auto)       │
│                                          │
│           [Reset to Defaults]            │
└─────────────────────────────────────────┘
```

### Phase 4: Persistent Configuration (Included in Phase 3)

Store calibration results in RuntimePlaybackConfig:

```dart
class RuntimePlaybackConfig {
  // Existing fields...
  
  /// Engine-specific optimal concurrency (discovered via calibration)
  final Map<String, int>? engineConcurrency;
  
  /// Whether each engine has been calibrated
  final Map<String, bool>? engineCalibrated;
  
  /// Measured RTF per engine (for UI display)
  final Map<String, double>? engineRtf;
}
```

---

## Implementation Tasks

### Phase 1: Enable Defaults (1 day)
- [ ] Set `parallelSynthesisEnabled = true` in PlaybackConfig
- [ ] Set `kokoroConcurrency = 2` as default
- [ ] Test on multiple devices

### Phase 2: Calibration Service (3-4 days)
- [ ] Create `EngineCalibrationService` class
- [ ] Add quick calibration method (3 segments × 3 concurrency levels)
- [ ] Store results in RuntimePlaybackConfig
- [ ] Add calibration dialog UI
- [ ] Hook into first-use voice selection

### Phase 3: Settings UI (2-3 days)
- [ ] Add "Audio Performance" section to Settings
- [ ] Show calibration status per engine
- [ ] Add "Optimize" button for uncalibrated engines
- [ ] Add collapsible "Advanced" section
- [ ] Add manual concurrency pickers
- [ ] Add "Reset to Defaults" button

### Phase 4: Integration (1-2 days)
- [ ] Wire BufferScheduler to use stored concurrency
- [ ] Update ParallelSynthesisOrchestrator to read config
- [ ] Add logging for debugging

---

## UI Mockup

### Calibration Dialog
```
┌────────────────────────────────────────┐
│  🔧 Optimizing Kokoro                   │
│                                         │
│  Testing synthesis performance...       │
│                                         │
│  [████████░░░░░░░░] 60%                 │
│                                         │
│  Testing concurrency level 2 of 3       │
│                                         │
│                      [Cancel]           │
└────────────────────────────────────────┘
```

### Calibration Result
```
┌────────────────────────────────────────┐
│  ✓ Kokoro Optimized!                    │
│                                         │
│  Your device works best with:           │
│  • Parallel synthesis: 3 threads        │
│  • Expected speedup: 1.6x               │
│                                         │
│  This means faster playback start       │
│  and smoother listening experience.     │
│                                         │
│                        [Got it]         │
└────────────────────────────────────────┘
```

---

## Risk Mitigation

### Memory Issues
- Use MemoryMonitor to pause parallel synthesis if memory gets low
- Fall back to sequential on low-RAM devices
- Set conservative defaults (concurrency 2)

### OOM Crashes
- Catch and handle OOM during calibration
- If concurrency N fails, mark N-1 as optimal
- Never enable concurrency higher than tested successfully

### User Confusion
- Hide advanced settings by default
- Use simple language ("Optimization" not "Concurrency")
- Show clear results with speedup percentages

---

## Success Metrics

1. **Buffering Time:** Reduce average buffering time by 30%+
2. **User Complaints:** No increase in crash/freeze reports
3. **Adoption:** 80%+ of users use auto-optimized settings

---

## Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Phase 1 | 1 day | Enable safe defaults |
| Phase 2 | 4 days | Auto-calibration service |
| Phase 3 | 3 days | Settings UI |
| Phase 4 | 2 days | Integration & testing |
| **Total** | **~10 days** | Full feature complete |

---

## Next Steps

1. **Immediate:** Enable `parallelSynthesisEnabled = true` with `kokoroConcurrency = 2`
2. **This Week:** Create EngineCalibrationService
3. **Next Week:** Add Settings UI with calibration buttons
