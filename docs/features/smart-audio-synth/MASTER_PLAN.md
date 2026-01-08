# Smart Audio Synthesis - Master Implementation Plan

## Executive Summary

This master plan consolidates all research, analysis, and strategy into a single actionable roadmap for eliminating user buffering across all three TTS engines (Supertonic, Piper, Kokoro).

**Current State**: 
- ✅ Benchmark test with accurate buffering calculation implemented
- ✅ Comprehensive research on TTS optimization completed
- ✅ Engine-specific analysis and plans created
- ✅ Auto-tuning system designed

**Goal**: Reduce buffering from current levels (5-21s) to **0 seconds** through smart pre-synthesis strategies.

**Timeline**: 8 weeks from kickoff to production deployment

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Current Architecture](#2-current-architecture)
3. [Benchmark Results Summary](#3-benchmark-results-summary)
4. [Strategic Approach](#4-strategic-approach)
5. [Implementation Phases](#5-implementation-phases)
6. [Engine-Specific Plans](#6-engine-specific-plans)
7. [Auto-Tuning System](#7-auto-tuning-system)
8. [Intelligent Cache Management](#8-intelligent-cache-management)
9. [Segment Readiness UI](#9-segment-readiness-ui)
10. [Testing Strategy](#10-testing-strategy)
11. [Success Metrics](#11-success-metrics)
12. [Risk Management](#12-risk-management)
13. [Resource Requirements](#13-resource-requirements)
14. [Timeline and Milestones](#14-timeline-and-milestones)

---

## 1. Problem Statement

### User Experience Issue

When users press "Play" on an audiobook:
1. First segment takes 5-21 seconds to synthesize (cold start)
2. User waits with loading spinner
3. Additional pauses occur during playback as synthesis falls behind
4. Total buffering: 5-15,000 seconds depending on engine

**Impact**: Poor user experience, app feels slow and unresponsive

### Technical Root Cause

**Just-In-Time (JIT) Synthesis**: Audio is generated only when needed, leading to:
- Cold start latency (model loading + first inference)
- Prefetch race conditions (synthesis vs playback speed)
- Cache misses on first playthrough

**Current Mitigation**: 20-word segmentation + background prefetch (insufficient)

---

## 2. Current Architecture

### Synthesis Pipeline

```
User Presses Play
       ↓
BookPlaybackController._playAudiobook()
       ↓
_ensureSegmentsReady() ← Checks cache
       ↓
   Cache Miss?
       ↓
TtsService.synthesizeSpeech() ← JIT synthesis (BLOCKS)
       ↓
AudioCache.put() ← Cache for replay
       ↓
PlaybackService.play() ← Start audio
       ↓
_startBackgroundPrefetch() ← Prefetch next segments
```

**Problem**: First segment is JIT, causing 5-21s wait

### Segmentation Logic

- **Current**: 20 words per segment (configurable)
- **Average Duration**: 8-10 seconds of audio per segment
- **Rationale**: Balance between granular control and synthesis overhead

### Caching

- **Storage**: `AudioCache` stores synthesized MP3 files
- **Key Format**: `{voiceId}_{bookId}_{segmentIndex}`
- **Eviction**: LRU (least recently used)
- **Persistence**: Survives app restarts

---

## 3. Benchmark Results Summary

### Test Methodology

**Sample Text**: 383-second excerpt from "Pride and Prejudice" (45 segments × 8.5s avg)

**Metrics Captured**:
- Total synthesis time
- Per-segment synthesis time
- Real-Time Factor (RTF) = synthesis_time / audio_duration
- User buffering time (simulates playback vs synthesis race)
- Buffering events (number of pauses)

**Cache Handling**: Cache cleared before each benchmark to ensure fresh synthesis

### Results Comparison

| Engine | RTF | First Segment | Avg Segment | Total Buffering | Events | Status |
|--------|-----|---------------|-------------|-----------------|--------|--------|
| **Supertonic M1** | 0.26x | 5.2s | 2.2s | 5.2s | 1 | ⭐ Excellent |
| **Piper Alan GB** | 0.38x | 7.4s | 2.9s | 9.8s | 2 | ⭐ Good |
| **Kokoro AF** | 2.76x | 21.4s | 23.4s | 15,351s | 45 | ❌ Critical |

### Key Insights

1. **RTF is Critical Threshold**:
   - RTF < 1.0: Synthesis faster than real-time → Prefetch works
   - RTF > 1.0: Synthesis slower than real-time → Prefetch fails

2. **First Segment Dominates**:
   - Supertonic: 100% of buffering (only buffering event)
   - Piper: 75% of buffering (first + second segment)
   - Kokoro: Every segment buffers (fundamental problem)

3. **Engine Characteristics**:
   - **Supertonic**: Fastest, most consistent (easiest to optimize)
   - **Piper**: Fast with minor prefetch timing issue (medium difficulty)
   - **Kokoro**: Slower than real-time (requires different strategy)

---

## 4. Strategic Approach

### Four-Pillar Strategy

#### 1. First-Segment Pre-Synthesis (Phase 1)
**Concept**: Synthesize first 1-2 segments BEFORE playback starts

**Implementation**:
```dart
Future<void> prepareForPlayback(Book book, int position) async {
  // Pre-synthesize first segment(s) before user sees play button
  await synthesizeSegment(segments[0]);
  if (needsSecondSegment) {
    await synthesizeSegment(segments[1]);
  }
}
```

**Impact**:
- Supertonic: 100% buffering elimination (only 1 event)
- Piper: 75% buffering reduction (first segment fixed)
- Kokoro: Minimal impact (needs more segments)

**Timeline**: 2 weeks implementation

#### 2. Extended Prefetch Window (Phase 2)
**Concept**: Start prefetching earlier and more aggressively

**Implementation**:
```dart
class SmartPrefetchManager {
  // Start prefetch immediately after first segment starts playing
  void startPrefetch(List<Segment> segments) {
    final prefetchWindow = _calculateWindow(rtf, deviceTier);
    for (var i = 1; i < prefetchWindow; i++) {
      _synthesizeInBackground(segments[i]);
    }
  }
}
```

**Impact**:
- Piper: Eliminates second-segment buffering (100% total elimination)
- Supertonic: Already perfect, no change
- Kokoro: Helps but insufficient (RTF too high)

**Timeline**: 1 week implementation (after Phase 1)

#### 3. Device-Adaptive Configuration (Phase 3)
**Concept**: Auto-tune synthesis strategy based on device capabilities

**Implementation**: Auto-Tuning System (see Section 7)

**Impact**:
- Flagship devices: More aggressive prefetch, parallel synthesis
- Mid-range devices: Balanced approach
- Budget devices: Conservative prefetch, single-threaded
- Kokoro-specific: Determine if real-time possible per device

**Timeline**: 2 weeks implementation

#### 4. Predictive Pre-Synthesis (Phase 4 - Future)
**Concept**: Synthesize ahead based on user behavior patterns

**Examples**:
- Pre-synthesize next chapter while user reads current chapter
- Overnight batch synthesis for planned books
- ML prediction of which chapters user will read next

**Impact**: Effectively eliminates ALL cold starts for predictable reading patterns

**Timeline**: 4 weeks research + implementation (post-MVP)

---

## 5. Implementation Phases

### Phase 1: Foundation (Weeks 1-2)

**Goal**: Implement core smart synthesis infrastructure

#### Tasks

1. **Create SmartSynthesisManager**
```dart
// packages/tts_engines/lib/src/smart_synthesis/smart_synthesis_manager.dart

abstract class SmartSynthesisManager {
  /// Called when user opens a book or navigates to chapter
  Future<void> prepareForPlayback(Book book, int startPosition);
  
  /// Start background prefetch during playback
  void startPrefetch(List<Segment> segments, int currentIndex);
  
  /// Get engine-specific configuration
  EngineConfig getConfig(DeviceTier tier);
  
  /// Measure synthesis performance
  Future<double> measureRTF();
}
```

2. **Implement Supertonic Adapter** (easiest engine)
```dart
class SupertonicSmartSynthesis extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    final segments = _segmentChapter(book, startPosition);
    
    // Pre-synthesize first segment only (fixes 100% of buffering)
    await synthesizeSegment(segments[0]);
    
    developer.log('✅ Supertonic ready for instant playback');
  }
  
  @override
  void startPrefetch(List<Segment> segments, int currentIndex) {
    // Aggressive prefetch (RTF 0.26x allows 3-4 segments ahead)
    final window = min(3, segments.length - currentIndex);
    for (var i = 1; i <= window; i++) {
      _synthesizeAsync(segments[currentIndex + i]);
    }
  }
}
```

3. **Integration with BookPlaybackController**
```dart
// lib/app/playback/book_playback_controller.dart

class BookPlaybackController extends AsyncNotifier<PlaybackState> {
  late final SmartSynthesisManager _synthesisManager;
  
  Future<void> openBook(Book book, int position) async {
    // Initialize appropriate synthesis manager for current voice
    _synthesisManager = _createManagerForVoice(currentVoice);
    
    // Pre-synthesize first segment(s)
    state = AsyncLoading();
    await _synthesisManager.prepareForPlayback(book, position);
    state = AsyncData(PlaybackState.ready);
  }
  
  Future<void> play() async {
    // Start playback immediately (first segment already cached)
    await _playbackService.play(_currentSegment);
    
    // Start background prefetch
    _synthesisManager.startPrefetch(_segments, _currentIndex);
  }
}
```

4. **Update UI to Show Preparation Status**
```dart
// lib/ui/screens/playback_screen.dart

Widget buildPlayButton() {
  return ref.watch(playbackControllerProvider).when(
    loading: () => CircularProgressIndicator(),  // Preparing audio...
    data: (state) => IconButton(
      icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
      onPressed: () => ref.read(playbackControllerProvider.notifier).play(),
    ),
    error: (e, st) => IconButton(
      icon: Icon(Icons.error),
      onPressed: null,
    ),
  );
}
```

**Deliverables**:
- ✅ SmartSynthesisManager interface
- ✅ Supertonic implementation (100% buffering elimination)
- ✅ Integration with playback controller
- ✅ UI updates for preparation status

**Testing**:
- Run benchmark before/after: Supertonic should show 0s buffering
- Test on real device with cache cleared
- Verify cold start experience improved

### Phase 2: Piper Optimization (Week 3)

**Goal**: Eliminate Piper's second-segment buffering (9.8s → 0s)

#### Root Cause Analysis

**Observed Behavior**:
- First segment: 7.4s synthesis time (user waits)
- Second segment: 2.4s buffering (prefetch too late)
- Remaining segments: No buffering (prefetch keeps up)

**Why Second Segment Buffers**:
1. Prefetch starts AFTER first segment begins playing
2. First segment audio duration: ~8.5s
3. Second segment synthesis: 2.9s
4. Problem: Prefetch triggered at t=0, second segment needed at t=8.5s
   - If second segment starts synthesizing at t=0, completes at t=2.9s → ✅ No buffering
   - If second segment starts synthesizing at t=1s, completes at t=3.9s → ✅ No buffering
   - Current: Starts at t=2s, completes at t=4.9s → ⚠️ Still early enough
   - **Actual issue**: Prefetch not starting immediately after first segment

#### Solution: Two-Phase Pre-Synthesis

```dart
class PiperSmartSynthesis extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    final segments = _segmentChapter(book, startPosition);
    
    // Phase 1: Pre-synthesize first segment (eliminates 75% buffering)
    await synthesizeSegment(segments[0]);
    
    // Phase 2: Immediately start second segment synthesis (non-blocking)
    if (segments.length > 1) {
      _synthesizeAsync(segments[1]);  // Don't await, runs in background
    }
    
    developer.log('✅ Piper ready for buffering-free playback');
  }
  
  @override
  void startPrefetch(List<Segment> segments, int currentIndex) {
    // Moderate prefetch (RTF 0.38x allows 2-3 segments ahead)
    final window = min(2, segments.length - currentIndex);
    for (var i = 1; i <= window; i++) {
      _synthesizeAsync(segments[currentIndex + i]);
    }
  }
}
```

**Key Insight**: Start second segment synthesis immediately when first completes, not when first starts playing.

**Deliverables**:
- ✅ Piper implementation (100% buffering elimination)
- ✅ Benchmark validation (0s buffering)

### Phase 3: Kokoro Optimization ⏸️ DEFERRED

> **Note**: Kokoro optimization has been moved to a separate project at `docs/features/kokoro-optimization/`. 
> This work is high-risk and may require breaking and rebuilding the Kokoro integration.
> See `../kokoro-optimization/README.md` for the dedicated project plan.

**Current Status**: Kokoro currently has RTF 2.76x (slower than real-time). Until optimization is complete, Kokoro will use the fallback strategy of pre-synthesizing multiple segments before playback.

---

### Phase 3: Auto-Tuning System (Week 4)

**Goal**: Automatic device performance profiling and configuration

#### Components

1. **Device Performance Profiler**
```dart
// packages/tts_engines/lib/src/smart_synthesis/device_profiler.dart

class DevicePerformanceProfiler {
  Future<DeviceProfile> profileDevice(Voice voice) async {
    // 30-second profiling test
    final testSegments = _generateTestSegments();
    final startTime = DateTime.now();
    
    for (var segment in testSegments) {
      await synthesizeSegment(segment);
    }
    
    final totalTime = DateTime.now().difference(startTime);
    final rtf = _calculateRTF(totalTime, testSegments);
    
    return DeviceProfile(
      voiceId: voice.id,
      measuredRTF: rtf,
      tier: _classifyTier(rtf),
      timestamp: DateTime.now(),
    );
  }
  
  DeviceTier _classifyTier(double rtf) {
    if (rtf < 0.3) return DeviceTier.flagship;
    if (rtf < 0.5) return DeviceTier.midRange;
    if (rtf < 0.8) return DeviceTier.budget;
    return DeviceTier.legacy;
  }
}
```

2. **Engine Configuration Manager**
```dart
class EngineConfigManager {
  EngineConfig getConfig(Voice voice, DeviceTier tier) {
    // Load engine-specific config for device tier
    final baseConfig = _loadBaseConfig(voice.engineType);
    final tierConfig = _loadTierConfig(voice.engineType, tier);
    
    return baseConfig.mergeWith(tierConfig);
  }
}

class EngineConfig {
  final int prefetchWindowSegments;
  final int maxConcurrentSynthesis;
  final bool preloadOnOpen;
  final int coldStartSegments;
  final BatteryStrategy batteryStrategy;
}
```

3. **Configuration Storage**
```json
// Stored in SharedPreferences
{
  "device_profiles": {
    "supertonic_m1": {
      "measured_rtf": 0.26,
      "tier": "flagship",
      "config": {
        "prefetch_window": 3,
        "max_concurrent": 2,
        "cold_start_segments": 1
      }
    },
    "piper_alan_gb": {
      "measured_rtf": 0.38,
      "tier": "flagship",
      "config": {
        "prefetch_window": 2,
        "max_concurrent": 2,
        "cold_start_segments": 1
      }
    },
    "kokoro_af": {
      "measured_rtf": 2.76,
      "tier": "unusable",
      "config": {
        "pre_synthesis_required": true,
        "prefetch_window": 0
      }
    }
  }
}
```

4. **First-Run Optimization Prompt**
```dart
// lib/ui/screens/optimization_prompt_screen.dart

class OptimizationPromptScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('⚡ Optimize Playback Performance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'We can automatically optimize audio synthesis for your device. '
            'This one-time test takes about 30 seconds.'
          ),
          SizedBox(height: 16),
          Text('Benefits:', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('• Eliminate buffering during playback'),
          Text('• Faster audio preparation'),
          Text('• Better battery efficiency'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Skip'),
        ),
        ElevatedButton(
          onPressed: () async {
            await _runOptimization(ref);
            Navigator.pop(context);
          },
          child: Text('Optimize Now'),
        ),
      ],
    );
  }
}
```

**Deliverables**:
- ✅ Device profiling system
- ✅ Configuration manager with tier-based configs
- ✅ First-run optimization prompt
- ✅ Settings screen integration

### Phase 5: Testing & Validation (Week 7)

**Goal**: Comprehensive testing across devices and scenarios

#### Test Matrix

| Device Tier | Engines | Scenarios | Expected Results |
|-------------|---------|-----------|------------------|
| Flagship | All 3 | Cold start, replay, chapter switching | 0s buffering (or Kokoro pre-synth workflow) |
| Mid-range | All 3 | Same scenarios | 0s buffering for Supertonic/Piper, Kokoro pre-synth |
| Budget | Supertonic, Piper | Same scenarios | 0s buffering with conservative prefetch |

#### Test Cases

1. **Cold Start Test**
   - Clear cache
   - Open book at chapter start
   - Press play
   - ✅ Verify: No waiting, immediate playback

2. **Chapter Switching Test**
   - During playback, jump to different chapter
   - Press play
   - ✅ Verify: First segment pre-synthesized, no buffering

3. **Replay Test**
   - Play through several segments
   - Jump back to beginning
   - Press play
   - ✅ Verify: Cache hit, instant playback

4. **Extended Playback Test**
   - Play through 50+ segments continuously
   - Monitor for buffering events
   - ✅ Verify: No pauses, smooth playback throughout

5. **Battery Impact Test**
   - Measure battery drain during 1-hour playback
   - Compare JIT vs pre-synthesis
   - ✅ Verify: <10% increase in battery consumption

6. **Storage Impact Test**
   - Synthesize 10 chapters
   - Check cache size
   - ✅ Verify: LRU eviction works, doesn't fill device

7. **Kokoro Workflow Test** (if Scenario C)
   - Select Kokoro voice
   - ✅ Verify warning shown
   - Tap "Prepare Chapter"
   - ✅ Verify progress indicator
   - Play after preparation
   - ✅ Verify 0 buffering during playback

**Automated Testing**:
```dart
// integration_test/smart_synthesis_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Smart Synthesis Integration Tests', () {
    testWidgets('Cold start - zero buffering', (tester) async {
      await tester.pumpWidget(MyApp());
      
      // Clear cache
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      
      // Open book
      await tester.tap(find.text('Pride and Prejudice'));
      await tester.pumpAndSettle();
      
      // Wait for preparation (should be < 3s for Supertonic)
      final startTime = DateTime.now();
      await tester.waitFor(find.byIcon(Icons.play_arrow), timeout: Duration(seconds: 5));
      final prepTime = DateTime.now().difference(startTime);
      
      expect(prepTime.inSeconds, lessThan(3), reason: 'First segment should pre-synthesize in <3s');
      
      // Press play
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      
      // Verify audio playing (no loading indicator)
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
```

**Deliverables**:
- ✅ Manual test results across device matrix
- ✅ Automated integration tests passing
- ✅ Performance benchmark comparison (before/after)
- ✅ Battery impact assessment

### Phase 6: Polish & Deployment (Week 8)

**Goal**: User-facing refinements and production deployment

#### Tasks

1. **UI Enhancements**
   - Loading states during preparation
   - Progress indicators for multi-segment pre-synthesis
   - Success notifications ("Audio ready!")
   - Error handling and retry logic

2. **Settings Screen Integration**
```dart
// lib/ui/screens/settings_screen.dart

Widget buildSmartSynthesisSettings() {
  return Column(
    children: [
      SwitchListTile(
        title: Text('Smart Audio Synthesis'),
        subtitle: Text('Pre-synthesize audio for instant playback'),
        value: smartSynthesisEnabled,
        onChanged: (value) => _toggleSmartSynthesis(value),
      ),
      ListTile(
        title: Text('Device Optimization'),
        subtitle: Text('Flagship device • Optimized for ${currentVoice.name}'),
        trailing: TextButton(
          child: Text('Re-optimize'),
          onPressed: () => _runOptimization(),
        ),
      ),
      ListTile(
        title: Text('Prefetch Strategy'),
        subtitle: Text(_getPrefetchDescription()),
        trailing: Icon(Icons.info_outline),
        onTap: () => _showPrefetchInfo(),
      ),
    ],
  );
}
```

3. **Analytics Integration**
```dart
class SynthesisAnalytics {
  void logBufferingEvent(String engineType, Duration bufferingTime) {
    analytics.logEvent(
      name: 'playback_buffering',
      parameters: {
        'engine': engineType,
        'duration_ms': bufferingTime.inMilliseconds,
        'device_tier': deviceTier.toString(),
      },
    );
  }
  
  void logPreSynthesisSuccess(String engineType, int segmentCount) {
    analytics.logEvent(
      name: 'pre_synthesis_complete',
      parameters: {
        'engine': engineType,
        'segments': segmentCount,
      },
    );
  }
}
```

4. **Documentation**
   - Update README with smart synthesis features
   - Add troubleshooting guide
   - Create user-facing FAQ

5. **Deployment**
   - Feature flag rollout (10% → 50% → 100%)
   - Monitor crash reports and analytics
   - Iterate based on user feedback

**Deliverables**:
- ✅ Polished UI with loading states
- ✅ Settings screen integration
- ✅ Analytics instrumentation
- ✅ Documentation updates
- ✅ Production deployment complete

---

## 6. Engine-Specific Plans

### Supertonic (⭐ Easy - 1 Week)

**Current Performance**:
- RTF: 0.26x (very fast)
- Buffering: 5.2s (1 event - first segment only)
- Strategy: Pre-synthesize first segment → 100% elimination

**Implementation**:
```dart
class SupertonicSmartSynthesis extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    final segments = _segmentChapter(book, startPosition);
    await synthesizeSegment(segments[0]);  // ~2-3s wait
  }
  
  @override
  EngineConfig getConfig(DeviceTier tier) {
    return EngineConfig(
      prefetchWindowSegments: tier == DeviceTier.flagship ? 3 : 2,
      maxConcurrentSynthesis: tier == DeviceTier.flagship ? 2 : 1,
      coldStartSegments: 1,
    );
  }
}
```

**Expected Outcome**: **0 seconds buffering** ✅

**Detailed Plan**: See `ENGINE_SUPERTONIC_PLAN.md`

---

### Piper (⭐⭐ Medium - 2 Weeks)

**Current Performance**:
- RTF: 0.38x (fast)
- Buffering: 9.8s (2 events - first 7.4s + second 2.4s)
- Strategy: Two-phase pre-synthesis (first + immediate second)

**Root Cause**: Prefetch starts too late for second segment

**Implementation**:
```dart
class PiperSmartSynthesis extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    final segments = _segmentChapter(book, startPosition);
    
    // Phase 1: Block on first segment
    await synthesizeSegment(segments[0]);  // ~3-4s wait
    
    // Phase 2: Immediately start second (non-blocking)
    if (segments.length > 1) {
      _synthesizeAsync(segments[1]);
    }
  }
  
  @override
  EngineConfig getConfig(DeviceTier tier) {
    return EngineConfig(
      prefetchWindowSegments: 2,
      maxConcurrentSynthesis: tier == DeviceTier.flagship ? 2 : 1,
      coldStartSegments: 1,  // Only block on first
      immediateSecondSegment: true,  // Start second immediately
    );
  }
}
```

**Expected Outcome**: **0 seconds buffering** ✅

**Detailed Plan**: See `ENGINE_PIPER_PLAN.md`

---

### Kokoro (⭐⭐⭐⭐⭐ Very Hard - 6 Weeks)

**Current Performance**:
- RTF: 2.76x (SLOWER than real-time)
- Buffering: 15,351s (45 events - every segment buffers)
- Challenge: Synthesis can't keep up with playback

**Three-Scenario Strategy**:

#### Scenario A: RTF < 1.0 Achieved (Optimistic - 20% probability)
Standard pre-synthesis approach, similar to Supertonic/Piper

#### Scenario B: RTF 1.0-1.5x (Borderline - 30% probability)
```dart
class KokoroHybridStrategy extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    // Pre-synthesize 4-6 segments (based on measured RTF)
    final preloadCount = (measuredRTF * 3).ceil();
    
    for (var i = 0; i < preloadCount; i++) {
      await synthesizeSegment(segments[i]);
      _notifyProgress(i + 1, preloadCount);  // Show progress bar
    }
  }
}
```

**User Experience**: 30-60s wait with progress bar, then smooth playback

#### Scenario C: RTF > 1.5x (Most Likely - 50% probability)
```dart
class KokoroPreSynthesisStrategy {
  // Full chapter pre-synthesis workflow
  Future<void> preSynthesizeChapter(Book book, int chapterIndex) async {
    final segments = _segmentChapter(book, chapterIndex);
    
    for (var i = 0; i < segments.length; i++) {
      await synthesizeSegment(segments[i]);
      _notifyProgress(i + 1, segments.length);
    }
  }
}
```

**User Experience**: 
- Show warning when selecting Kokoro
- "Prepare Chapter" button in chapter list
- 5-10 minute preparation per chapter
- 0 buffering after preparation

**Optimization Roadmap**:

**Week 4**: Deep profiling
- Component timing (phonemization, inference, postprocessing)
- Phoneme warning investigation
- Memory/GC analysis
- Parallel synthesis testing

**Week 5**: Model optimization
- Test float32/float16 quantization (vs current int8)
- ONNX Runtime tuning (threads, graph optimization, GPU/NPU)
- Session warm-up and reuse
- Native implementation evaluation

**Week 6**: Strategy implementation based on achieved RTF

**Expected Outcomes**:
- Best case: RTF 0.8-1.0x → Real-time possible with pre-synthesis
- Likely case: RTF 1.2-1.8x → Hybrid workflow (extended pre-load)
- Worst case: RTF > 1.8x → Pre-synthesis only workflow

**Detailed Plan**: See `ENGINE_KOKORO_PLAN.md`

---

## 7. Auto-Tuning System

### Architecture

```
User First Run
      ↓
Optimization Prompt (optional)
      ↓
DevicePerformanceProfiler.profileDevice()
      ↓
30-second benchmark test
      ↓
Calculate RTF & classify device tier
      ↓
EngineConfigManager.saveProfile()
      ↓
SmartSynthesisManager uses optimized config
```

### Device Tier Classification

| Tier | RTF Range | Characteristics | Config |
|------|-----------|-----------------|--------|
| **Flagship** | <0.3 | Snapdragon 8 Gen 3, Apple A17 Pro | Aggressive prefetch (3-4 segments), 2x parallel |
| **Mid-range** | 0.3-0.5 | Snapdragon 7 Gen 2, Apple A15 | Moderate prefetch (2 segments), 2x parallel |
| **Budget** | 0.5-0.8 | Snapdragon 6 Gen 1, older devices | Conservative prefetch (1 segment), single-threaded |
| **Legacy** | >0.8 | Old devices, entry-level phones | Minimal prefetch, single-threaded, warnings |

### Configuration Schema

```dart
class EngineConfig {
  // Prefetch behavior
  final int prefetchWindowSegments;      // How many segments ahead to synthesize
  final int maxConcurrentSynthesis;      // Parallel synthesis threads
  final bool preloadOnOpen;              // Pre-synthesize when opening book
  final int coldStartSegments;           // How many to pre-synthesize before playback
  
  // Battery optimization
  final BatteryStrategy batteryStrategy; // Aggressive/Balanced/Conservative
  final bool pausePrefetchOnLowBattery;  // Stop prefetch <20% battery
  
  // Engine-specific
  final bool warmupSession;              // Warm up ONNX session (Kokoro)
  final bool immediateSecondSegment;     // Start second segment immediately (Piper)
  
  // Kokoro-specific
  final bool preSynthesisRequired;       // Requires full chapter prep
  final int hybridPreloadCount;          // Segments to preload in hybrid mode
}
```

### User-Facing Features

1. **First-Run Optimization Prompt**
   - Appears after first voice download
   - Optional 30-second test
   - "Skip" button for later

2. **Settings Screen**
   - Shows current device tier
   - "Re-optimize" button
   - Manual override options

3. **Per-Voice Optimization**
   - Each voice profiled separately
   - Results stored persistently
   - Auto-updates if performance changes

**Detailed Design**: See `AUTO_TUNING_SYSTEM.md`

---

## 8. Intelligent Cache Management

### Overview

Users need control over how much storage the audio cache consumes, and the system needs intelligent eviction to maximize cache hit rates within user-defined limits.

### Implementation Status: ✅ Core Complete

- ✅ `CacheEntryMetadata` - Metadata model with all required fields
- ✅ `EvictionScoreCalculator` - Multi-factor scoring algorithm
- ✅ `IntelligentCacheManager` - Full cache manager implementation
- ✅ `CacheCompressor` - Long-term storage compression with Opus
- ⏳ User settings UI (pending)
- ⏳ Native Opus encoder integration (pending)

### Key Features

#### User-Configurable Storage Quota

- **Settings slider**: 500 MB to 10 GB (default based on device storage)
- **Quick presets**: 500 MB, 1 GB, 2 GB, 5 GB
- **Cache breakdown visualization**: Per-book and per-voice usage
- **Clear cache button** with confirmation

Default quotas by device storage:
| Device Storage | Default Quota |
|----------------|---------------|
| < 32 GB | 500 MB |
| 32-64 GB | 1 GB |
| 64-128 GB | 2 GB |
| > 128 GB | 5 GB |

#### Intelligent Cache Eviction

Multi-factor scoring algorithm (rather than simple LRU):

| Factor | Weight | Description |
|--------|--------|-------------|
| **Recency** | 30% | Recent access is valuable |
| **Reading Position** | 30% | Segments near current position are valuable |
| **Frequency** | 20% | Frequently accessed segments are valuable |
| **Book Progress** | 15% | Books in-progress more valuable than finished |
| **Voice Match** | 5% | Current voice cache is more valuable |

**Eviction Priority**:
- **High Priority to Keep**: Currently playing, next 5 segments, active book
- **Medium Priority**: Same chapter, other in-progress books, recent synthesis
- **Low Priority**: Finished books, old voice, segments behind reading position

#### Long-Term Storage Compression

Compress older cache entries using Opus codec for ~10x space savings:

| Compression Level | Bitrate | Ratio | Quality |
|-------------------|---------|-------|---------|
| None | N/A | 1x | Fastest access |
| Light | 64 kbps | 6x | High quality |
| **Standard** | 32 kbps | 10x | Good quality (default) |
| Aggressive | 24 kbps | 15x | Maximum savings |

**Hot/Cold Cache**: Recently accessed entries (<1 hour) stay uncompressed; older entries are compressed.

#### Proactive Cache Management

- Pre-emptive eviction before large synthesis batches
- Gradual book unloading after completion
- Emergency eviction on low disk space

### Implementation Timeline

Part of **Week 7-8** cache management sprint:

| Task | Duration | Status |
|------|----------|--------|
| Core cache manager with metadata | 3 days | ✅ Complete |
| Intelligent eviction algorithm | 2 days | ✅ Complete |
| Compression module | 2 days | ✅ Complete |
| User settings UI (cache size slider) | 2 days | ✅ Complete |
| Disk space monitoring | 1 day | ✅ Complete |
| Native Opus integration | 2 days | ⏳ Pending |
| Testing & polish | 2 days | ⏳ Pending |

**Detailed Design**: See `INTELLIGENT_CACHE_MANAGEMENT.md`

---

## 9. Segment Readiness UI

### Overview

Visual feedback shows users which text segments are ready for playback. Non-synthesized text appears greyed out; synthesized text appears at full opacity.

### Visual Design

```
Segment States (visual opacity):
├── Ready (synthesized): 100% opacity - full clarity
├── Synthesizing: 60% opacity + optional progress
├── Queued: 40% opacity - slightly visible
└── Not Queued: 30% opacity - clearly greyed
```

### User Experience

1. **When chapter loads**: Text starts mostly greyed
2. **As synthesis progresses**: Text "lights up" from the beginning
3. **During playback**: Current segment highlighted, upcoming text gradually becomes clear
4. **Smooth transitions**: 300ms animated fade from grey to full

### Implementation

```dart
// Opacity calculated from segment state
double get opacity {
  switch (state) {
    case SegmentState.ready:
      return 1.0;
    case SegmentState.synthesizing:
      return 0.6 + progress * 0.4; // 0.6-1.0
    case SegmentState.queued:
      return 0.4;
    case SegmentState.notQueued:
      return 0.3;
  }
}
```

### Integration Points

1. **Buffer Scheduler**: Reports synthesis start/progress/complete
2. **Audio Cache**: Initializes ready state from cached segments
3. **Playback Screen**: Renders text with appropriate opacity

### Accessibility

- Minimum opacity ensures WCAG AA contrast compliance
- Screen reader announces segment readiness state
- Alternative: progress bar option for users who prefer explicit indicators

### Implementation Timeline

Part of **Week 8** UI polish:

| Task | Duration |
|------|----------|
| SegmentReadinessProvider | 2 hours |
| ReadableText widget | 4 hours |
| Buffer scheduler integration | 2 hours |
| Animation polish | 2 hours |

**Detailed Design**: See `SEGMENT_READINESS_UI.md`

---

## 10. Testing Strategy

### Unit Tests

```dart
// packages/tts_engines/test/smart_synthesis/smart_synthesis_manager_test.dart

void main() {
  group('SmartSynthesisManager', () {
    test('prepareForPlayback synthesizes first segment', () async {
      final manager = SupertonicSmartSynthesis();
      final book = TestData.sampleBook;
      
      await manager.prepareForPlayback(book, 0);
      
      verify(mockTtsService.synthesizeSpeech(any)).called(1);
    });
    
    test('startPrefetch respects prefetch window', () async {
      final manager = SupertonicSmartSynthesis();
      final segments = TestData.generateSegments(10);
      
      manager.startPrefetch(segments, 0);
      
      // Flagship config: prefetch 3 segments
      await Future.delayed(Duration(seconds: 1));
      verify(mockTtsService.synthesizeSpeech(any)).called(3);
    });
  });
}
```

### Integration Tests

```dart
// integration_test/playback_buffering_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  testWidgets('Zero buffering during playback', (tester) async {
    // Clear cache
    await AudioCache.instance.clear();
    
    // Open book
    await tester.tap(find.text('Test Book'));
    await tester.pumpAndSettle();
    
    // Measure time to play button ready
    final startTime = DateTime.now();
    await tester.waitFor(find.byIcon(Icons.play_arrow));
    final prepTime = DateTime.now().difference(startTime);
    
    expect(prepTime.inSeconds, lessThan(3));
    
    // Start playback
    await tester.tap(find.byIcon(Icons.play_arrow));
    
    // Monitor for buffering events over 60 seconds
    final bufferingEvents = <DateTime>[];
    for (var i = 0; i < 60; i++) {
      await tester.pump(Duration(seconds: 1));
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
        bufferingEvents.add(DateTime.now());
      }
    }
    
    expect(bufferingEvents, isEmpty, reason: 'Should have zero buffering events');
  });
}
```

### Benchmark Tests

```dart
// test/benchmark/synthesis_benchmark_test.dart

void main() {
  test('Supertonic achieves RTF < 0.3', () async {
    final rtf = await benchmarkEngine(EngineType.supertonic);
    expect(rtf, lessThan(0.3));
  });
  
  test('Piper achieves RTF < 0.5', () async {
    final rtf = await benchmarkEngine(EngineType.piper);
    expect(rtf, lessThan(0.5));
  });
  
  test('Pre-synthesis eliminates first-segment buffering', () async {
    final manager = SupertonicSmartSynthesis();
    await manager.prepareForPlayback(testBook, 0);
    
    final bufferingTime = await measureBuffering();
    expect(bufferingTime.inMilliseconds, equals(0));
  });
}
```

### Device Testing Matrix

| Device | OS | Engines | Status |
|--------|-----|---------|--------|
| Pixel 8 Pro | Android 14 | All 3 | ✅ Primary test device |
| Samsung S23 | Android 14 | All 3 | ⏳ Secondary flagship |
| Pixel 6a | Android 13 | All 3 | ⏳ Mid-range test |
| iPhone 15 Pro | iOS 17 | All 3 | ⏳ iOS flagship |
| Moto G Power | Android 12 | Supertonic, Piper | ⏳ Budget device |

---

## 11. Success Metrics

### Primary KPIs

| Metric | Baseline (Current) | Target (Post-Implementation) |
|--------|-------------------|------------------------------|
| **Supertonic Buffering** | 5.2s | 0s (100% elimination) |
| **Piper Buffering** | 9.8s | 0s (100% elimination) |
| **Kokoro Buffering** | 15,351s | 0s (after pre-synthesis) or <5s (hybrid) |
| **Time to Play (Cold Start)** | 5-21s | <3s (Supertonic/Piper), varies (Kokoro) |
| **User-Reported Buffering** | TBD (baseline) | <1% users report buffering |

### Secondary KPIs

| Metric | Target |
|--------|--------|
| **Battery Impact** | <10% increase vs baseline |
| **Storage Impact** | <500MB cache size (with LRU eviction) |
| **First-Time Setup Duration** | <60s (including optimization) |
| **Crash Rate** | <0.1% (no regression) |
| **User Satisfaction** | >4.5/5 stars for playback experience |

### Validation Criteria

✅ **Phase 1 Success**: Supertonic shows 0s buffering in benchmark  
✅ **Phase 2 Success**: Piper shows 0s buffering in benchmark  
✅ **Phase 3 Success**: Kokoro strategy implemented with clear UX  
✅ **Phase 4 Success**: Auto-tuning works across device tiers  
✅ **Phase 5 Success**: Cache stays within user quota, intelligent eviction works  
✅ **Phase 6 Success**: Segment readiness UI shows correct opacity states  
✅ **Phase 7 Success**: Integration tests pass on all test devices  
✅ **Phase 8 Success**: Production deployment with <0.1% crash rate  

---

## 12. Risk Management

### High Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Kokoro never achieves RTF < 1.0 | 70% | High | Accept Scenario C (pre-synthesis workflow) with excellent UX |
| Battery drain increases significantly | 30% | High | Implement battery-aware prefetch, pause on low battery |
| Storage fills up on devices | 40% | Medium | Aggressive LRU eviction, user-configurable cache size |
| Users confused by Kokoro warnings | 50% | Medium | A/B test warning copy, provide clear alternatives |

### Medium Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Pre-synthesis delays perceived as bug | 40% | Medium | Progress indicators, "Preparing audio..." messaging |
| Performance varies across Android vendors | 60% | Medium | Device-specific profiling handles this automatically |
| Parallel synthesis causes crashes | 20% | High | Extensive testing, fallback to single-threaded |
| ONNX optimization has minimal effect | 50% | Medium | Multiple optimization strategies (quantization, threads, GPU) |

### Low Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Regression in current functionality | 10% | High | Comprehensive integration tests, feature flag rollout |
| Analytics data insufficient | 20% | Low | Instrument all key events, monitor daily |

---

## 13. Resource Requirements

### Development Team

| Role | Time Commitment | Duration |
|------|----------------|----------|
| Senior Flutter Developer | 100% | 8 weeks |
| Platform Engineer (Android) | 25% | 3 weeks (Kokoro optimization) |
| QA Engineer | 50% | 2 weeks (testing phase) |
| UX Designer | 25% | 1 week (UI polish) |

### Infrastructure

- **CI/CD**: Existing pipeline sufficient
- **Test Devices**: 5 devices across tiers (listed in Section 8)
- **Cloud Services**: None required (all on-device processing)

### External Dependencies

- **None**: All work within existing codebase and dependencies

---

## 14. Timeline and Milestones

### Gantt Chart (8 Weeks)

> **Note**: Kokoro optimization has been moved to a separate project.
> See `docs/features/kokoro-optimization/` for the dedicated 4-6 week plan.

```
Week 1: Foundation ✅
├─ SmartSynthesisManager interface
├─ Supertonic implementation
└─ Integration with playback controller

Week 2: Foundation (continued) ✅
├─ UI updates (loading states)
├─ Resource-aware prefetch (Phase 2)
└─ Testing and validation

Week 3: Piper Optimization ✅
├─ Piper implementation
├─ Benchmark validation
└─ Testing

Week 4: Auto-Tuning System
├─ Device profiler
├─ Configuration manager
├─ First-run optimization prompt
└─ Settings integration

Week 5: Intelligent Cache Management ✅ (Core complete)
├─ Core cache manager with metadata
├─ Intelligent eviction algorithm
├─ User quota settings UI ⏳
└─ Disk space monitoring ⏳

Week 6: Segment Readiness UI + Cache Polish ✅ (Core complete)
├─ SegmentReadinessProvider
├─ ReadableText widget with opacity states
├─ Buffer scheduler integration
├─ Cache analytics & insights ⏳

Week 7: Testing & Validation
├─ Device matrix testing
├─ Integration tests
├─ Battery impact assessment
├─ Cache eviction testing
└─ Bug fixes

Week 8: Polish & Deployment
├─ UI refinements
├─ Analytics instrumentation
├─ Documentation
└─ Production rollout (10% → 50% → 100%)
```

### Key Milestones

| Date | Milestone | Deliverables | Status |
|------|-----------|--------------|--------|
| **End of Week 2** | Foundation Complete | Supertonic/Piper 0s buffering achieved | ✅ |
| **End of Week 3** | Resource-Aware Complete | Battery-aware prefetch working | ✅ |
| **End of Week 4** | Auto-Tuning Complete | Device profiling working | ✅ |
| **End of Week 5** | Cache Management Complete | User quota + intelligent eviction | ✅ |
| **End of Week 6** | Segment Readiness UI Complete | Text opacity states working | ✅ |
| **End of Week 7** | Testing Complete | All tests passing, ready for production | ⏳ |
| **End of Week 8** | Production Deployment | Feature live for 100% users | ⏳ |

---

## Conclusion

This master plan consolidates 8 weeks of work to eliminate buffering for Supertonic and Piper TTS engines through smart pre-synthesis strategies. Kokoro optimization has been moved to a dedicated project due to its complexity and risk.

Key achievements:

✅ **Supertonic**: 100% buffering elimination (5.2s → 0s) via single-segment pre-synthesis  
✅ **Piper**: 100% buffering elimination (9.8s → 0s) via two-phase pre-synthesis  
⏸️ **Kokoro**: Deferred to separate project (see `docs/features/kokoro-optimization/`)  
✅ **Auto-Tuning**: Device-adaptive configuration for optimal performance across all device tiers  
✅ **Intelligent Cache**: User-configurable storage quota (slider 0.5-10 GB) with smart eviction  
✅ **Segment Readiness UI**: Visual feedback showing text opacity based on synthesis state  

The plan is realistic, phased, and includes comprehensive testing and risk mitigation. Success is defined not just by technical metrics but by user experience: **instant playback with zero frustration**.

---

## Appendix: Related Documentation

- **BUFFERING_REDUCTION_STRATEGY.md**: Research-backed strategies and industry comparison
- **TECHNICAL_IMPLEMENTATION.md**: Detailed architecture and code samples
- **ENGINE_SUPERTONIC_PLAN.md**: Supertonic-specific optimization (1 week)
- **ENGINE_PIPER_PLAN.md**: Piper-specific optimization (2 weeks)
- **../kokoro-optimization/README.md**: Kokoro optimization project (separate project, 4-6 weeks)
- **AUTO_TUNING_SYSTEM.md**: Device profiling and auto-configuration
- **INTELLIGENT_CACHE_MANAGEMENT.md**: User-configurable storage quota and smart eviction
- **SEGMENT_READINESS_UI.md**: Text opacity states for synthesis feedback
- **CURRENT_ARCHITECTURE.md**: Existing JIT + prefetch system
- **LOGGING_IMPLEMENTATION.md**: Logging patterns and debugging guide

---

**Document Version**: 1.3  
**Last Updated**: 2026-01-09  
**Status**: In Progress (Weeks 1-6 Complete, Week 7-8 Pending)  
**Total Estimated Effort**: 8 weeks (1 senior developer)
