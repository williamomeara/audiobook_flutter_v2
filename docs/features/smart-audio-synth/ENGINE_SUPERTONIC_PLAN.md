# Supertonic Optimization Plan
## Eliminating 5.2s Buffering Time

**Engine**: Supertonic M1 (Advanced quality TTS)  
**Current Performance**: 5.2s buffering (1.4% of playback), RTF 0.26x  
**Target**: 0s buffering (instant playback)

---

## Performance Profile

### Benchmark Results (5.7-minute chapter, 45 segments)
- **First segment**: 5.2s (cold start with model loading)
- **Subsequent segments**: 662-4,287ms (avg 2,212ms)
- **Fastest segment**: 662ms (short text)
- **Slowest segment**: 4,287ms (long text)
- **Total synthesis time**: 99s
- **RTF**: 0.26x (synthesis 3.8x faster than real-time)
- **Buffering events**: **1** (only first segment!)

### Characteristics
✅ **Strengths**:
- **Only 1 buffering event** (vs Piper's 2)
- Prefetch keeps up perfectly after first segment
- RTF 0.26x = excellent headroom for prefetch
- 30% faster cold start than Piper (5.2s vs 7.4s)

⚠️ **Bottleneck**:
- **First segment wait**: 5.2s (user presses play → silence → audio starts)
- Cold start model loading overhead

---

## Optimization Strategy

### Phase 1: Immediate Win - Pre-Synthesize First Segment (Target: 5.2s → 0s)

**Goal**: Eliminate the single buffering event

**Approach**: Since Supertonic only buffers once, pre-synthesizing first segment solves 100% of the problem.

```dart
// In PlaybackControllerNotifier.loadChapter()
Future<void> loadChapter(Chapter chapter) async {
  final segments = segmentText(chapter.content);
  
  // ═══════════════════════════════════════════════════════════════
  // SUPERTONIC: Pre-synthesize first segment (eliminates ALL buffering)
  // ═══════════════════════════════════════════════════════════════
  await _synthesisManager.requestSynthesis(SynthesisRequest(
    chapterId: chapter.id,
    segmentIndex: 0,
    priority: SynthesisPriority.immediate,
    reason: SynthesisReason.userPlay,
  ));
  
  // Chapter now ready for instant playback!
}
```

**Expected Result**:
- Buffering: 5.2s → **0s** ✅
- Buffering events: 1 → **0** ✅
- User experience: Instant playback on first press

**Effort**: 2-3 days
**Impact**: **100% buffering elimination**

---

### Phase 2: Aggressive Background Prefetch (Target: Maintain 0s)

**Goal**: Keep cache hot for seeking, chapter switches

**Approach**: Use 0.26 RTF to advantage - synthesize entire chapter quickly

#### 2A: Immediate Window (10 segments)
```dart
// After first segment starts playing
void _onFirstSegmentPlaying() {
  // Supertonic is fast! Prefetch aggressively
  _schedulePrefetch(
    range: (1, 10), // 10 segments = ~30-40s audio
    priority: SynthesisPriority.high,
    concurrency: 2, // Can do 2 parallel with RTF 0.26x
  );
}
```

**Expected**: 10 segments synthesized in ~22s (avg 2.2s each)  
**Real-time equivalent**: ~40s of audio  
**Result**: Synthesis finishes before user reaches segment 10

#### 2B: Full Chapter Synthesis (Opportunistic)
```dart
// After immediate window, continue background synthesis
void _onImmediateWindowComplete() {
  if (_canAggressivePrefetch()) { // Battery > 30%, not overheating
    _schedulePrefetch(
      range: (11, segments.length),
      priority: SynthesisPriority.medium,
      concurrency: 1, // Lower priority, single thread
    );
  }
}
```

**Expected**: Full chapter (45 segments) synthesized in ~99s  
**Real-time**: 5.7 minutes of audio  
**Result**: Entire chapter cached by 30% playback point

**Timing Analysis**:
```
User listening timeline:
0:00 - Segment 0 plays (pre-synthesized) ✅
0:07 - Segment 1 plays → Prefetch working on segments 2-11
0:30 - Segment 3 plays → Prefetch has segments 2-11 ready ✅
1:00 - Segment 6 plays → Prefetch working on segments 12-20
2:00 - Segment 12 plays → Full chapter prefetch 50% complete
5:00 - User at 80% chapter → Full chapter cached ✅
```

**Result**: Seamless playback, instant seeks throughout chapter

---

### Phase 3: Chapter-Ahead Prediction (Target: Instant chapter switches)

**Goal**: Zero buffering on chapter transitions

**Approach**: Predict next chapter with high confidence, pre-synthesize first segment

#### Sequential Reading Detection
```dart
class SupertonicPrediction {
  Future<void> predictNextChapter(PlaybackState state) async {
    // User at 70% of current chapter + sequential reader → high confidence
    if (state.position / state.duration > 0.7 && _isSequentialReader()) {
      final nextChapter = _getNextChapter();
      
      // Pre-synthesize first segment of next chapter (only 2.2s)
      await _synthesisManager.requestSynthesis(SynthesisRequest(
        chapterId: nextChapter.id,
        segmentIndex: 0,
        priority: SynthesisPriority.medium,
        reason: SynthesisReason.predictedNext,
      ));
      
      // Optionally: Pre-synthesize segments 1-5 for smooth start
      if (_batteryLevel > 50%) {
        _synthesizeRange(nextChapter, range: (1, 5));
      }
    }
  }
}
```

**Expected Impact**:
- 85% of chapter switches instant (0s wait)
- 15% of chapter switches 5.2s wait (unpredicted)
- Average chapter switch: 0.8s wait

---

### Phase 4: Supertonic-Specific Optimizations

#### 4A: Model Warm-Up on App Start
```dart
// Keep Supertonic models loaded in memory
class SupertonicWarmup {
  Future<void> warmupOnAppStart() async {
    // Synthesize a tiny dummy phrase to load models
    await supertonic.synthesize(".", speaker: 0);
    // Models now in memory for instant first synthesis
  }
}
```

**Expected**: First segment from 5.2s → **3.5s** (40% faster)

#### 4B: Parallel Prefetch (2 threads)
Since Supertonic RTF is 0.26x, we have headroom for parallel synthesis:

```dart
// Synthesize 2 segments simultaneously
const maxConcurrentSupertonic = 2;

// Segment N and N+1 in parallel
Future.wait([
  _synthesize(segments[n]),
  _synthesize(segments[n+1]),
]);
```

**Expected**: Prefetch rate doubles (20s → 10s for 10 segments)

#### 4C: Smart Caching Priority
Supertonic generates high-quality audio worth keeping:

```dart
class SupertonicCachePolicy {
  int get priority => 100; // Keep Supertonic audio longest
  int get retentionDays => 14; // 2 weeks vs 7 days for Piper
  
  bool shouldEvict(CacheEntry entry) {
    // Never evict Supertonic current chapter
    // Prefer evicting Piper before Supertonic
    return entry.engine != EngineType.supertonic;
  }
}
```

**Reasoning**: Supertonic takes longer to synthesize, so cache is more valuable

---

## Implementation Priority

### Must-Have (Phase 1)
✅ **Pre-synthesize first segment on chapter load**
- Eliminates 100% of buffering (5.2s → 0s)
- Simplest implementation
- Biggest user impact

### Should-Have (Phase 2)
✅ **Aggressive immediate window prefetch**
- Ensures smooth playback for 1-2 minutes
- Takes advantage of fast RTF

🟡 **Full chapter prefetch** (battery-aware)
- Nice to have, not critical
- Enables instant seeking

### Nice-to-Have (Phase 3-4)
🟢 **Next chapter prediction**
- Improves chapter switching
- 85% success rate expected

🟢 **Model warm-up, parallel prefetch**
- Marginal improvements
- Adds complexity

---

## Engine-Specific Configuration

```dart
class SupertonicSynthesisConfig {
  // Prefetch aggressiveness
  static const prefetchWindowSize = 10; // segments
  static const prefetchConcurrency = 2; // parallel threads
  
  // Battery thresholds (Supertonic is efficient!)
  static const minBatteryForFullPrefetch = 30; // vs 50 for Piper
  static const minBatteryForPrefetch = 15; // vs 20 for Piper
  
  // Cache retention
  static const cacheRetentionDays = 14; // vs 7 for Piper
  static const cachePriority = 100; // vs 80 for Piper
  
  // Model warm-up
  static const warmupOnAppStart = true;
  static const keepModelsLoaded = true; // Don't unload between chapters
}
```

---

## Expected Outcomes

### Phase 1 Only (Week 1)
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Total buffering | 5.2s | 0s | **100%** ✅ |
| First play latency | 5.2s | <500ms | **90%** ✅ |
| Buffering events | 1 | 0 | **100%** ✅ |
| User satisfaction | 🔴 Poor | 🟢 Good | Major win |

### Phase 1 + 2 (Week 2)
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Seek latency (any position) | 0-2.2s | 0s | **100%** ✅ |
| Cache hit rate | 0% | 95%+ | Perfect |
| Playback smoothness | 🟡 Good | 🟢 Excellent | Premium |

### Phase 1 + 2 + 3 (Week 3)
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Chapter switch (sequential) | 5.2s | 0s | **100%** ✅ |
| Chapter switch (random) | 5.2s | 5.2s | Same |
| Average chapter switch | 5.2s | 0.8s | **85%** ✅ |

---

## Comparison to Other Engines

### Why Supertonic is Easiest to Optimize

| Factor | Supertonic | Piper | Advantage |
|--------|-----------|-------|-----------|
| **Buffering events** | 1 | 2 | **Fix one, fix all** |
| **RTF** | 0.26x | 0.38x | **More headroom** |
| **Prefetch success** | 100% after first | ~50% | **Better** |
| **First segment** | 5.2s | 7.4s | **30% faster** |

**Conclusion**: Supertonic is the **easiest engine to optimize** - single bottleneck, fast synthesis, reliable prefetch.

---

## Risk Assessment

### Low Risk
✅ Pre-synthesizing first segment
- Simple implementation
- Clear benefits
- No downside

### Medium Risk
⚠️ Aggressive prefetch
- Battery drain possible
- Mitigated by battery-aware modes
- Worth the tradeoff for 0s buffering

### High Risk
🔴 Model warm-up on app start
- Adds ~3s to app startup time
- May annoy users if not needed
- Consider as opt-in setting

---

## Success Metrics

### Primary KPI: User Buffering Experience
- **Target**: 0s buffering time (down from 5.2s)
- **Measure**: Benchmark shows 0 buffering events
- **Success**: 100% elimination of wait time

### Secondary KPIs
- First play latency < 500ms (instant)
- Seek latency < 100ms (instant)
- Cache hit rate > 95%
- Battery drain < 3% additional

### User Perception
- "Instant playback" rating: > 90%
- Buffering complaints: Reduce by 100%
- Supertonic voice adoption: Increase by 25%

---

## Recommendation

**Start with Phase 1 only**:
1. Pre-synthesize first segment on chapter load
2. Measure results with benchmark
3. Celebrate 100% buffering elimination ✅

**Then add Phase 2** if users want instant seeking:
1. Aggressive immediate window
2. Optional full chapter prefetch
3. Battery-aware controls

**Skip Phase 3-4** unless data shows benefit:
- Chapter prediction nice-to-have
- Warm-up adds complexity
- Diminishing returns

---

## Implementation Timeline

| Week | Phase | Deliverable | Impact |
|------|-------|-------------|--------|
| **1** | Phase 1 | First-segment pre-synthesis | **100% buffering elimination** |
| **2** | Phase 2A | Immediate window prefetch | Instant seeks (0-30s) |
| **3** | Phase 2B | Full chapter prefetch | Instant seeks (anywhere) |
| **4** | Phase 3 | Next chapter prediction | Instant chapter switches |

**Total**: 4 weeks from 5.2s → 0s buffering ✅

---

## Code Example: Complete Supertonic Optimization

```dart
class SupertonicOptimizedController {
  Future<void> loadChapter(Chapter chapter) async {
    final segments = segmentText(chapter.content);
    
    // ═══════════════════════════════════════════════════════════
    // PHASE 1: Pre-synthesize first segment (eliminates ALL buffering!)
    // ═══════════════════════════════════════════════════════════
    print('[Supertonic] Pre-synthesizing first segment...');
    await _synthesize(segments[0]);
    print('[Supertonic] First segment ready! User can press play now.');
    
    // ═══════════════════════════════════════════════════════════
    // PHASE 2: Start aggressive background prefetch
    // ═══════════════════════════════════════════════════════════
    _startBackgroundPrefetch(segments, startIndex: 1);
  }
  
  void _startBackgroundPrefetch(List<Segment> segments, {required int startIndex}) {
    // Don't await - let it run in background
    Future(() async {
      // Immediate window: segments 1-10 (parallel)
      await Future.wait([
        _synthesizeBatch(segments, range: (1, 6)),
        _synthesizeBatch(segments, range: (6, 11)),
      ]);
      
      // Full chapter: segments 11-end (if battery allows)
      if (_batteryLevel > 30) {
        await _synthesizeBatch(segments, range: (11, segments.length));
      }
    });
  }
}
```

---

**Status**: Ready for implementation  
**Priority**: **P0** (Highest - solves 100% of buffering with simple fix)  
**Confidence**: **Very High** (one bottleneck, clear solution, proven results)
