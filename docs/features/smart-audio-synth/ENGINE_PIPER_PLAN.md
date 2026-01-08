# Piper Optimization Plan
## Reducing 9.8s Buffering Time

**Engine**: Piper Alan GB Medium (Fast, efficient TTS)  
**Current Performance**: 9.8s buffering (2.9% of playback), RTF 0.38x  
**Target**: <1s buffering (near-instant playback)

---

## Performance Profile

### Benchmark Results (5.7-minute chapter, 45 segments)
- **First segment**: 7.4s (cold start with voice loading)
- **Second segment**: 2.4s (prefetch fell behind)
- **Subsequent segments**: 0s (prefetch caught up!)
- **Average synthesis time**: 2,948ms per segment
- **Fastest segment**: 886ms (short text)
- **Slowest segment**: 7,432ms (first segment, includes loading)
- **Total synthesis time**: 133s
- **RTF**: 0.38x (synthesis 2.6x faster than real-time)
- **Buffering events**: **2** (first + second segments)

### Characteristics
⚠️ **Challenges**:
- **2 buffering events** (vs Supertonic's 1)
- Second segment pause indicates prefetch timing issue
- Slower cold start than Supertonic (7.4s vs 5.2s)
- RTF 0.38x = good but less headroom than Supertonic (0.26x)

✅ **Strengths**:
- Fast synthesis after warm-up (886ms-5.7s range)
- Lightweight, battery-efficient
- Prefetch works after segment 2
- Good for longer listening sessions

---

## Optimization Strategy

### Phase 1: Eliminate First Segment Buffering (Target: 7.4s → 0s)

**Goal**: Pre-synthesize first segment to eliminate primary bottleneck

**Approach**: Same as Supertonic, but need to account for slower cold start

```dart
// In PlaybackControllerNotifier.loadChapter()
Future<void> loadChapter(Chapter chapter) async {
  final segments = segmentText(chapter.content);
  
  // ═══════════════════════════════════════════════════════════════
  // PIPER: Pre-synthesize first segment (eliminates 75% of buffering)
  // ═══════════════════════════════════════════════════════════════
  print('[Piper] Pre-synthesizing first segment...');
  final startTime = DateTime.now();
  
  await _synthesisManager.requestSynthesis(SynthesisRequest(
    chapterId: chapter.id,
    segmentIndex: 0,
    priority: SynthesisPriority.immediate,
    reason: SynthesisReason.userPlay,
    timeout: Duration(seconds: 15), // Piper can take 7.4s
  ));
  
  final duration = DateTime.now().difference(startTime);
  print('[Piper] First segment ready in ${duration.inMilliseconds}ms');
}
```

**Expected Result**:
- Buffering: 9.8s → **2.4s** (75% reduction)
- First segment: Instant playback ✅
- Second segment: Still 2.4s wait (prefetch issue remains)

**Effort**: 2-3 days
**Impact**: **75% buffering reduction**

---

### Phase 2: Fix Second Segment Buffering (Target: 2.4s → 0s)

**Problem**: Why does second segment buffer?

**Root Cause Analysis**:
```
Timeline:
0.0s - First segment starts playing (pre-synthesized)
7.9s - First segment finishes → Prefetch for segment 1 should start
      BUT: First segment synthesis just completed (7.4s)
      Prefetch for segment 1 starts now, needs 2.9s
10.3s - Second segment ready (7.9s + 2.4s delay)

Problem: Prefetch starts AFTER first segment plays, not DURING
```

**Solution**: Start prefetch IMMEDIATELY after first segment synthesizes

#### 2A: Immediate Prefetch Trigger
```dart
Future<void> loadChapter(Chapter chapter) async {
  final segments = segmentText(chapter.content);
  
  // Synthesize first segment
  await _synthesize(segments[0]);
  
  // ═══════════════════════════════════════════════════════════════
  // PIPER FIX: Start prefetch IMMEDIATELY (don't wait for playback)
  // ═══════════════════════════════════════════════════════════════
  _startImmediatePrefetch(segments, startIndex: 1);
  
  // User can press play now - first segment ready,
  // second segment will be ready by the time it's needed!
}

void _startImmediatePrefetch(List<Segment> segments, {required int startIndex}) {
  // Don't await - run in background
  Future(() async {
    print('[Piper] Prefetching segment $startIndex immediately');
    await _synthesize(segments[startIndex]);
    print('[Piper] Segment $startIndex ready before playback needs it!');
    
    // Continue prefetching segments 2-10
    for (var i = startIndex + 1; i < startIndex + 10 && i < segments.length; i++) {
      await _synthesize(segments[i]);
    }
  });
}
```

**Timing with Fix**:
```
0.0s - loadChapter() called
0.0s → 7.4s - First segment synthesizing
7.4s - First segment done, prefetch starts for segment 1
7.4s → 10.3s - Second segment synthesizing (2.9s)
10.3s - Second segment ready

User presses play at 8.0s:
8.0s - First segment plays immediately ✅
15.9s - Need second segment → Already ready! (synthesized at 10.3s) ✅
```

**Expected Result**:
- Second segment buffering: 2.4s → **0s** ✅
- Total buffering: 9.8s → **0s** (100% elimination)

#### 2B: Parallel First + Second Synthesis (Advanced)
For even better results, synthesize first TWO segments in parallel:

```dart
Future<void> loadChapter(Chapter chapter) async {
  final segments = segmentText(chapter.content);
  
  // ═══════════════════════════════════════════════════════════════
  // PIPER ADVANCED: Synthesize first 2 segments in parallel
  // ═══════════════════════════════════════════════════════════════
  await Future.wait([
    _synthesize(segments[0]),
    _synthesize(segments[1]),
  ]);
  
  // Both segments ready! Guaranteed smooth start.
  _startBackgroundPrefetch(segments, startIndex: 2);
}
```

**Expected**:
- Both segments ready in ~7.4s (parallel synthesis)
- Guaranteed 0s buffering for first 2 segments
- Trade-off: Slightly longer initial load (7.4s vs 7.4s+2.9s sequential)

**Recommendation**: Use 2A (sequential with immediate prefetch) first. Only use 2B if 2A doesn't fully solve it.

---

### Phase 3: Aggressive Extended Prefetch (Target: Maintain 0s)

**Goal**: Keep prefetch ahead of playback for entire chapter

**Approach**: Use RTF 0.38x to synthesize 10-15 segments ahead

```dart
void _startExtendedPrefetch() {
  // After segments 0-1 ready, aggressively prefetch 2-15
  Future(() async {
    // Batch 1: Segments 2-7 (high priority)
    for (var i = 2; i < 8 && i < segments.length; i++) {
      await _synthesize(segments[i]);
    }
    
    // Batch 2: Segments 8-15 (medium priority, if battery > 30%)
    if (_batteryLevel > 30) {
      for (var i = 8; i < 16 && i < segments.length; i++) {
        await _synthesize(segments[i]);
      }
    }
  });
}
```

**Expected**:
- 15 segments cached = ~1.5 minutes of audio
- Synthesis time for 15 segments: ~44s (avg 2.9s each)
- User listening time for 15 segments: ~90s
- Result: Prefetch stays ahead ✅

---

### Phase 4: Piper-Specific Optimizations

#### 4A: Voice Pre-Loading
Piper's cold start (7.4s) includes voice model loading. Pre-load on app start:

```dart
class PiperWarmup {
  Future<void> preloadVoiceOnAppStart(String voiceId) async {
    // Load voice model into memory
    await piperAdapter.loadVoice(voiceId);
    // Keep in memory until app closes
  }
}
```

**Expected**: First segment from 7.4s → **~4s** (45% faster cold start)

#### 4B: Sherpa-ONNX Session Reuse
Piper uses Sherpa-ONNX. Reuse sessions instead of recreating:

```dart
class PiperSessionManager {
  OfflineTts? _session;
  
  Future<OfflineTts> getSession(String voiceId) async {
    if (_session != null) {
      return _session!; // Reuse existing session
    }
    
    _session = await OfflineTts.create(voiceId);
    return _session!;
  }
}
```

**Expected**: Subsequent segment synthesis 10-15% faster

#### 4C: Smart Segment Batching
Group short segments to reduce overhead:

```dart
// Instead of synthesizing "No struggle." (38 chars) alone,
// combine with next segment:
// "No struggle. Just a man lying peacefully..." (104 chars)
// Then split audio file into two cache entries

class PiperBatchOptimizer {
  bool shouldBatch(Segment a, Segment b) {
    return a.text.length < 50 && b.text.length < 50;
  }
}
```

**Expected**: 20-30% faster for short segments (reduces initialization overhead)

---

## Engine-Specific Configuration

```dart
class PiperSynthesisConfig {
  // Prefetch aggressiveness
  static const prefetchWindowSize = 15; // segments (more than Supertonic)
  static const prefetchConcurrency = 1; // single thread (RTF tighter)
  
  // Pre-synthesis on chapter load
  static const preSynthesizeCount = 2; // First 2 segments (vs 1 for Supertonic)
  
  // Battery thresholds (Piper is efficient but slower)
  static const minBatteryForFullPrefetch = 40; // vs 30 for Supertonic
  static const minBatteryForPrefetch = 20; // vs 15 for Supertonic
  
  // Cache retention
  static const cacheRetentionDays = 7; // vs 14 for Supertonic
  static const cachePriority = 80; // vs 100 for Supertonic
  
  // Model warm-up
  static const preloadVoiceOnAppStart = true;
  static const keepSessionAlive = true;
}
```

---

## Expected Outcomes

### Phase 1 Only (Week 1)
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Total buffering | 9.8s | 2.4s | **75%** ✅ |
| First segment wait | 7.4s | <500ms | **93%** ✅ |
| Buffering events | 2 | 1 | **50%** |
| User satisfaction | 🔴 Poor | 🟡 Okay | Improvement |

### Phase 1 + 2 (Week 2)
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Total buffering | 9.8s | 0s | **100%** ✅ |
| Second segment wait | 2.4s | 0s | **100%** ✅ |
| Buffering events | 2 | 0 | **100%** ✅ |
| User satisfaction | 🔴 Poor | 🟢 Good | Major win |

### Phase 1 + 2 + 3 (Week 3)
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Seek latency (0-90s) | 0-2.9s | 0s | **100%** ✅ |
| Cache hit rate | 0% | 85%+ | Excellent |
| Playback smoothness | 🟡 Good | 🟢 Excellent | Premium |

---

## Comparison to Supertonic

### Why Piper is Harder to Optimize

| Factor | Piper | Supertonic | Challenge |
|--------|-------|------------|-----------|
| **Buffering events** | 2 | 1 | **Need to fix 2 issues** |
| **Cold start** | 7.4s | 5.2s | **30% slower** |
| **RTF** | 0.38x | 0.26x | **Less headroom** |
| **Second segment** | Buffers | Doesn't buffer | **Extra problem** |

**Conclusion**: Piper requires **2-phase fix** (first segment + second segment) vs Supertonic's single fix.

---

## Phased Implementation

### Phase 1: First Segment Pre-Synthesis (Week 1)
**Priority**: **P0** (Critical)  
**Effort**: 2-3 days  
**Impact**: 75% buffering reduction

```dart
// Simple, proven solution
await _synthesize(segments[0]);
_startImmediatePrefetch(segments, startIndex: 1);
```

### Phase 2: Second Segment Fix (Week 2)
**Priority**: **P0** (Critical)  
**Effort**: 1-2 days  
**Impact**: 100% buffering elimination

**Option A**: Immediate prefetch (recommended)
```dart
// Start prefetch right after first segment, don't wait for playback
_startImmediatePrefetch(segments, startIndex: 1);
```

**Option B**: Parallel synthesis (if 2A insufficient)
```dart
// Synthesize first 2 segments in parallel
await Future.wait([_synthesize(segments[0]), _synthesize(segments[1])]);
```

### Phase 3: Extended Prefetch (Week 3)
**Priority**: **P1** (High)  
**Effort**: 2-3 days  
**Impact**: Instant seeking, smooth chapter playback

```dart
// Prefetch 15 segments ahead
_startExtendedPrefetch();
```

### Phase 4: Piper-Specific Optimizations (Week 4+)
**Priority**: **P2** (Nice to have)  
**Effort**: 3-4 days  
**Impact**: 20-30% faster synthesis, better battery life

- Voice pre-loading
- Session reuse
- Segment batching

---

## Risk Assessment

### Low Risk ✅
- Pre-synthesize first segment (proven approach)
- Immediate prefetch trigger (simple timing change)

### Medium Risk ⚠️
- Parallel first+second synthesis (more complex, higher battery use)
- Extended prefetch (battery drain on low battery devices)

### High Risk 🔴
- Voice pre-loading on app start (adds startup delay)
- Segment batching (complex, potential cache invalidation issues)

---

## Success Metrics

### Primary KPI: User Buffering Experience
- **Phase 1 Target**: 9.8s → 2.4s (75% reduction)
- **Phase 2 Target**: 2.4s → 0s (100% elimination)
- **Success Criteria**: 0 buffering events after Phase 2

### Secondary KPIs
- First play latency < 500ms
- Second play latency < 500ms (no pause)
- Cache hit rate > 85% after first listen
- Battery drain < 4% additional

### User Perception
- "Smooth playback" rating: > 85%
- Buffering complaints: Reduce by 90%
- Piper voice satisfaction: Increase by 20%

---

## Recommended Approach

### Week 1: Phase 1 (First Segment)
**Do this**:
1. Pre-synthesize first segment on chapter load
2. Start immediate prefetch for segment 1
3. Measure: Should see 75% reduction (9.8s → 2.4s)

**Don't do yet**:
- Parallel synthesis (wait and see if needed)
- Voice pre-loading (adds complexity)

### Week 2: Phase 2 (Second Segment)
**Do this**:
1. Test Phase 1 results
2. If second segment still buffers, adjust prefetch timing
3. Measure: Should see 100% elimination (2.4s → 0s)

**If still issues**:
- Try parallel first+second synthesis
- Increase prefetch urgency

### Week 3+: Phase 3 (Extended Prefetch)
**Only if**:
- Phases 1-2 successful
- Users want instant seeking
- Battery impact acceptable

---

## Code Example: Complete Piper Optimization

```dart
class PiperOptimizedController {
  Future<void> loadChapter(Chapter chapter) async {
    final segments = segmentText(chapter.content);
    
    // ═══════════════════════════════════════════════════════════
    // PHASE 1: Pre-synthesize first segment
    // ═══════════════════════════════════════════════════════════
    print('[Piper] Pre-synthesizing first segment...');
    await _synthesize(segments[0]);
    print('[Piper] First segment ready!');
    
    // ═══════════════════════════════════════════════════════════
    // PHASE 2: Start immediate prefetch (fixes second segment)
    // ═══════════════════════════════════════════════════════════
    _startImmediatePrefetch(segments);
  }
  
  void _startImmediatePrefetch(List<Segment> segments) {
    Future(() async {
      // Critical: Segment 1 (fixes second segment buffering)
      print('[Piper] Prefetching segment 1 immediately');
      await _synthesize(segments[1]);
      print('[Piper] Segment 1 ready before playback needs it!');
      
      // Extended: Segments 2-15 (smooth playback)
      for (var i = 2; i < 16 && i < segments.length; i++) {
        if (_shouldContinuePrefetch()) {
          await _synthesize(segments[i]);
        } else {
          break; // Stop if battery low or user paused
        }
      }
    });
  }
  
  bool _shouldContinuePrefetch() {
    return _batteryLevel > 20 && _isPlaying;
  }
}
```

---

## Comparison Matrix: Piper vs Supertonic

| Aspect | Piper Plan | Supertonic Plan | Winner |
|--------|-----------|-----------------|---------|
| **Complexity** | Medium (2 fixes) | Low (1 fix) | Supertonic |
| **Effort** | 2 weeks | 1 week | Supertonic |
| **First segment** | 7.4s → 0s | 5.2s → 0s | Both |
| **Second segment** | 2.4s → 0s | Already 0s | Supertonic |
| **Implementation risk** | Medium | Low | Supertonic |
| **Battery impact** | Higher | Lower | Supertonic |

**Recommendation**: Implement Supertonic optimization first (easier, faster, lower risk). Use learnings to inform Piper optimization.

---

**Status**: Ready for implementation  
**Priority**: **P0** (High - but after Supertonic)  
**Confidence**: **High** (clear root causes, proven solutions, manageable risks)  
**Dependencies**: None (can implement alongside Supertonic)
