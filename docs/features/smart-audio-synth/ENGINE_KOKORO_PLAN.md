# Kokoro TTS Engine - Buffering Elimination Plan

## Executive Summary

**Current Performance**: Kokoro AF voice shows SEVERE performance issues with RTF 2.76x (slower than real-time), resulting in 15,351 seconds of total buffering across a 383-second sample (4024% of playback time). This is the most challenging engine to optimize.

**Key Challenge**: Unlike Supertonic (RTF 0.26x) and Piper (RTF 0.38x), Kokoro's RTF > 1.0 means synthesis is fundamentally slower than real-time playback. Traditional prefetch strategies CANNOT eliminate buffering because synthesis will always fall behind.

**Strategic Approach**: 
1. **Immediate**: Deep analysis and optimization of Kokoro's ONNX inference performance
2. **Phase 1**: Model optimization and inference tuning to achieve RTF < 1.0
3. **Phase 2**: If RTF < 1.0 achieved, apply pre-synthesis strategies
4. **Fallback**: If optimization fails, recommend Kokoro for "pre-synthesize entire chapter" workflow only

---

## 1. Benchmark Results Analysis

### Performance Metrics

```
ENGINE: Kokoro AF
TEST DURATION: 1054 seconds (17.6 minutes)
SAMPLE: 383 seconds of audio (45 segments × 8.5s avg)

REAL-TIME FACTOR (RTF): 2.76x ⚠️ CRITICAL
  → Takes 2.76 seconds to synthesize 1 second of audio
  → 176% SLOWER than real-time
  → Impossible to keep pace with playback

USER BUFFERING: 15,351 seconds total (255.8 minutes)
  → 4024% of playback time
  → First segment: 21.4s wait
  → 44 additional pauses during playback
  → 45 total buffering events (EVERY segment buffers)

SEGMENT SYNTHESIS TIME:
  → Average: 23.4 seconds per segment
  → Range: 8.5s - 52s (extreme variability)
  → First segment (cold start): 21.4s
  → Slowest segment (#28): 52s for 221 characters
```

### Comparison with Other Engines

| Metric | Supertonic | Piper | Kokoro | Kokoro vs Best |
|--------|------------|-------|--------|----------------|
| RTF | 0.26x ✅ | 0.38x ✅ | 2.76x ❌ | **10.6x slower** |
| First Segment | 5.2s | 7.4s | 21.4s | **4.1x slower** |
| Avg Segment | 2.2s | 2.9s | 23.4s | **10.6x slower** |
| Total Buffering | 5.2s | 9.8s | 15,351s | **2,952x worse** |
| Buffering Events | 1 | 2 | 45 | **45x more** |

**Verdict**: Kokoro is currently **UNUSABLE** for real-time playback. Every segment causes user buffering.

---

## 2. Root Cause Analysis

### 2.1 Why Is Kokoro So Slow?

Based on benchmark logs and ONNX inference patterns:

#### Observation 1: Unknown Phoneme Warnings
```
WARN: Unknown phonemes: \\U+025a
WARN: Unknown phonemes: \\U+0329
```

**Impact**: These warnings appear frequently and may indicate:
- Kokoro's phonemizer (espeak-ng) producing unexpected outputs
- ONNX model not trained on these phoneme codes
- Fallback logic or error handling slowing down inference
- Possible Unicode normalization issues

**Hypothesis**: Phonemization errors cause model confusion, increasing inference time.

#### Observation 2: Extreme Segment Variability (8.5s - 52s)

Segments taking 20+ seconds:
- Segment 1: 21.4s (238 chars) - cold start
- Segment 2: 25.8s (203 chars)
- Segment 6: 26.1s (224 chars)
- Segment 10: 20.2s (223 chars)
- Segment 15: 39.7s (238 chars)
- Segment 16: 31.8s (221 chars)
- **Segment 28: 52s (221 chars)** ← OUTLIER

**Pattern**: No clear correlation between character count and synthesis time. Segment 28 (221 chars) took 52s, while segment 5 (228 chars) took only 8.5s.

**Hypothesis**: Model performance degradation based on:
- Specific phoneme sequences (complex words)
- Sentence structure complexity
- Model attention mechanism bottlenecks
- ONNX Runtime optimization failures for certain inputs

#### Observation 3: ONNX Model Size and Quantization

**Current Model**: `kokoro-v0_19.int8.onnx` (int8 quantization)

**Potential Issues**:
- Int8 quantization may reduce accuracy, causing:
  - More inference iterations for convergence
  - Quality degradation requiring error correction
  - Suboptimal performance on certain phoneme patterns
- Model architecture not optimized for mobile/edge devices
- No GPU acceleration on Android (CPU-only inference)

**Hypothesis**: Int8 quantization trades accuracy for size, but Kokoro's architecture may not handle quantization well, resulting in slower inference.

#### Observation 4: Lack of Streaming/Chunking

**Current Behavior**: Kokoro synthesizes entire segments atomically (no streaming).

**Problem**: Kokoro's autoregressive model generates audio frame-by-frame, but:
- User must wait for entire segment completion before playback starts
- No partial audio delivery (unlike ElevenLabs streaming approach)
- Single-threaded inference blocks until done

**Hypothesis**: Streaming inference could reduce first-byte latency significantly.

---

### 2.2 Comparison with Sherpa-ONNX Implementation

**Sherpa-ONNX** is a known high-performance Kokoro inference implementation. Key differences:

| Feature | Our Implementation | Sherpa-ONNX |
|---------|-------------------|-------------|
| ONNX Runtime | Flutter onnxruntime_flutter | Native C++ binding |
| Threading | Dart isolates | Native threads |
| Model Loading | Cold start per session | Persistent session reuse |
| GPU Support | None | CUDA/DirectML/CoreML |
| Optimization | Basic | Advanced (graph optimization) |
| Streaming | No | Yes (chunked inference) |

**Key Insight**: Sherpa-ONNX achieves near-real-time performance through:
1. Native C++ bindings (lower overhead than Flutter FFI)
2. Session pooling and reuse (no cold start penalty)
3. GPU acceleration where available
4. Graph optimization passes at model load time

---

### 2.3 Device Considerations

**Test Device**: Assumed mid-range Android device (based on Piper/Supertonic performance being reasonable)

**Kokoro-Specific Issues**:
- Larger model size (~500MB vs ~20MB Piper) → slower loading
- More complex architecture → higher memory bandwidth requirements
- No quantization-aware training → int8 performance degradation
- CPU-only inference on Android (no GPU/NPU acceleration)

**Device Impact**:
- Flagship devices (Snapdragon 8 Gen 3): Might achieve RTF 1.0-1.5x (still too slow)
- Mid-range devices: Current RTF 2.76x
- Budget devices: Expected RTF 4-5x (completely unusable)

---

## 3. Optimization Strategies (Phased)

### Phase 1: Deep Performance Analysis (Week 1)

**Goal**: Identify specific bottlenecks in current implementation.

#### 1.1 Detailed Profiling
```dart
// Add granular timing to platform_android_tts/lib/src/kokoro_tts_adapter.dart

class KokoroPerformanceProfiler {
  final List<ProfileEvent> events = [];
  
  void recordEvent(String name, Duration duration) {
    events.add(ProfileEvent(name, duration));
  }
  
  Map<String, dynamic> generateReport() {
    return {
      'phonemization_time': _avgTime('phonemize'),
      'model_inference_time': _avgTime('inference'),
      'postprocessing_time': _avgTime('postprocess'),
      'total_time': _avgTime('total'),
      'cold_start_penalty': events.first.duration.inMilliseconds,
    };
  }
}

// Usage in synthesis pipeline:
Future<Uint8List> synthesize(String text) async {
  final profiler = KokoroPerformanceProfiler();
  
  // 1. Phonemization
  final t1 = DateTime.now();
  final phonemes = await _phonemize(text);
  profiler.recordEvent('phonemize', DateTime.now().difference(t1));
  
  // 2. Model inference
  final t2 = DateTime.now();
  final audio = await _runInference(phonemes);
  profiler.recordEvent('inference', DateTime.now().difference(t2));
  
  // 3. Postprocessing
  final t3 = DateTime.now();
  final processed = await _postprocess(audio);
  profiler.recordEvent('postprocess', DateTime.now().difference(t3));
  
  // Log report
  developer.log('Kokoro Profile: ${profiler.generateReport()}');
  
  return processed;
}
```

**Expected Insights**:
- Is phonemization the bottleneck? (espeak-ng performance)
- Is ONNX inference the bottleneck? (model complexity)
- Is postprocessing slow? (audio encoding)
- What's the cold start penalty? (model loading)

#### 1.2 Phoneme Warning Investigation
```dart
// Add detailed logging for phoneme warnings
class KokoroPhonemeAnalyzer {
  final Set<String> unknownPhonemes = {};
  
  void analyzeText(String text, List<String> phonemes) {
    // Check for unknown phoneme patterns
    for (var phoneme in phonemes) {
      if (phoneme.contains(r'\U+')) {
        unknownPhonemes.add(phoneme);
        developer.log('Unknown phoneme in "$text": $phoneme');
      }
    }
  }
  
  Map<String, int> generateReport() {
    // Return frequency map of unknown phonemes
    final Map<String, int> frequency = {};
    for (var phoneme in unknownPhonemes) {
      frequency[phoneme] = (frequency[phoneme] ?? 0) + 1;
    }
    return frequency;
  }
}
```

**Action Items**:
- Identify which input texts trigger unknown phonemes
- Check if these correlate with slow segments
- Test with phoneme normalization/cleanup
- Consider alternative phonemizer (g2p) if espeak-ng is problematic

#### 1.3 Memory and GC Analysis
```dart
// Add memory tracking
import 'dart:developer' as developer;

class MemoryTracker {
  void logMemoryUsage(String phase) {
    final timeline = Timeline.now;
    developer.postEvent('memory_checkpoint', {
      'phase': phase,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

// Usage:
Future<Uint8List> synthesize(String text) async {
  memoryTracker.logMemoryUsage('before_synthesis');
  final audio = await _synthesizeInternal(text);
  memoryTracker.logMemoryUsage('after_synthesis');
  return audio;
}
```

**Check For**:
- Large memory allocations causing GC pressure
- Memory leaks in ONNX session management
- Buffer copying overhead

**Deliverables**:
- Detailed performance report identifying primary bottleneck(s)
- Phoneme frequency analysis with slowdown correlation
- Memory usage patterns and GC impact assessment

---

### Phase 2: Model Optimization (Week 2-3)

**Goal**: Reduce Kokoro RTF from 2.76x to <1.0x through model and inference optimization.

#### 2.1 Test Alternative Quantization

**Current**: `kokoro-v0_19.int8.onnx` (int8 quantization)

**Test Options**:
1. **Float32 model** (if available)
   - Higher accuracy, may improve convergence speed
   - Larger file size (~2GB), longer load time
   - Better inference performance if quantization is bottleneck

2. **Float16 model** (if available)
   - Balance between accuracy and size
   - 2x smaller than float32
   - May achieve better RTF than int8

**Implementation**:
```dart
// Add model variant selection to manifests/voices_manifest.json
{
  "kokoro_af": {
    "variants": [
      {
        "precision": "int8",
        "file": "kokoro-v0_19.int8.onnx",
        "size": 500000000,
        "expected_rtf": 2.76
      },
      {
        "precision": "float16",
        "file": "kokoro-v0_19.fp16.onnx",
        "size": 1000000000,
        "expected_rtf": 1.2  // estimated
      },
      {
        "precision": "float32",
        "file": "kokoro-v0_19.fp32.onnx",
        "size": 2000000000,
        "expected_rtf": 0.8  // estimated
      }
    ]
  }
}

// Auto-select based on device tier (from AUTO_TUNING_SYSTEM.md)
class KokoroModelSelector {
  String selectVariant(DeviceTier tier, int availableStorageMB) {
    if (tier == DeviceTier.flagship && availableStorageMB > 2000) {
      return 'float32';  // Best quality, fastest inference
    } else if (tier == DeviceTier.midRange && availableStorageMB > 1000) {
      return 'float16';  // Balanced
    } else {
      return 'int8';  // Smallest, but slowest
    }
  }
}
```

**Expected Impact**: 
- Float32: Potentially RTF 0.8-1.2x (MIGHT achieve real-time)
- Float16: Potentially RTF 1.2-1.8x (still too slow, but better)

#### 2.2 ONNX Runtime Optimization

**Current Config**: Default ONNX Runtime settings

**Optimizations to Test**:

```dart
// platform_android_tts/lib/src/kokoro_tts_adapter.dart

class OptimizedKokoroSession {
  late final OrtSession session;
  
  Future<void> initialize(String modelPath) async {
    // 1. Session options with performance flags
    final sessionOptions = OrtSessionOptions()
      ..setInterOpNumThreads(4)  // Parallel ops
      ..setIntraOpNumThreads(4)  // Thread pool size
      ..setGraphOptimizationLevel(
        GraphOptimizationLevel.ORT_ENABLE_ALL
      )  // Max optimization
      ..enableCpuMemArena()  // Reduce allocation overhead
      ..enableMemPattern();  // Optimize memory access
    
    // 2. Execution provider order (try GPU first)
    final providers = [
      'CoreMLExecutionProvider',  // iOS GPU
      'NnapiExecutionProvider',   // Android NPU
      'CPUExecutionProvider',     // Fallback
    ];
    
    for (var provider in providers) {
      try {
        sessionOptions.appendExecutionProvider(provider);
        developer.log('✅ Enabled: $provider');
      } catch (e) {
        developer.log('❌ Unavailable: $provider');
      }
    }
    
    // 3. Load model with optimizations
    session = OrtSession.fromFile(modelPath, sessionOptions);
    
    // 4. Warm up (remove cold start penalty)
    await _warmUp();
  }
  
  Future<void> _warmUp() async {
    // Synthesize short test phrase to initialize internal state
    await synthesize("Hello.");
    developer.log('🔥 Kokoro session warmed up');
  }
}
```

**Expected Impact**:
- Graph optimization: 10-20% faster inference
- Thread pool tuning: 10-30% faster on multi-core CPUs
- GPU/NPU provider: 2-5x faster if available
- Warm-up: Eliminates first-segment cold start penalty

**Total Expected RTF Improvement**: 2.76x → 1.0-1.5x (still borderline)

#### 2.3 Phoneme Preprocessing Optimization

**Problem**: Unknown phonemes causing fallback logic delays

**Solution**: Preprocess and normalize phonemes

```dart
class PhonemeNormalizer {
  // Map of problematic phonemes to safe alternatives
  static const Map<String, String> normalizationMap = {
    r'\U+025a': 'ɚ',  // Replace Unicode escape with actual IPA
    r'\U+0329': '̩',   // Syllabic marker
    // Add more based on Phase 1 analysis
  };
  
  String normalize(String phonemes) {
    var normalized = phonemes;
    normalizationMap.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });
    return normalized;
  }
  
  // Alternative: Strip unknown phonemes entirely
  String stripUnknown(String phonemes) {
    return phonemes.replaceAll(RegExp(r'\\U\+[0-9a-f]+'), '');
  }
}

// Integration:
Future<Uint8List> synthesize(String text) async {
  var phonemes = await _phonemize(text);
  phonemes = PhonemeNormalizer().normalize(phonemes);  // Clean up
  return await _runInference(phonemes);
}
```

**Expected Impact**: 5-15% faster inference if warnings are causing slowdowns

#### 2.4 Consider Native Implementation

**If Flutter ONNX Runtime is bottleneck**:

```kotlin
// android/app/src/main/kotlin/com/example/audiobook/KokoroNativeEngine.kt

import ai.onnxruntime.*
import java.nio.FloatBuffer

class KokoroNativeEngine(modelPath: String) {
    private val env = OrtEnvironment.getEnvironment()
    private val sessionOptions = OrtSession.SessionOptions().apply {
        setOptimizationLevel(OptLevel.ALL_OPT)
        setInterOpNumThreads(4)
        setIntraOpNumThreads(4)
    }
    private val session = env.createSession(modelPath, sessionOptions)
    
    fun synthesize(phonemes: FloatArray): FloatArray {
        val inputTensor = OnnxTensor.createTensor(
            env, 
            FloatBuffer.wrap(phonemes)
        )
        
        val results = session.run(mapOf("input" to inputTensor))
        val outputTensor = results[0] as OnnxTensor
        
        return outputTensor.floatBuffer.array()
    }
}
```

**Expected Impact**: 20-40% faster than Flutter FFI overhead

**Trade-off**: More complex native code maintenance

---

### Phase 3: Inference Optimization (Week 4)

**Goal**: If RTF < 1.0 achieved, apply prefetch strategies. Otherwise, implement alternative workflows.

#### Scenario A: RTF < 1.0 Achieved ✅

**Apply Standard Pre-synthesis Strategy** (similar to Supertonic/Piper):

```dart
// Pre-synthesize first 2 segments before playback
class KokoroSmartSynthesis extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    final segments = segmentChapter(book, startPosition);
    
    // Kokoro needs longer warm-up due to model complexity
    await _warmUpSession();
    
    // Pre-synthesize first 2 segments (due to variability)
    await Future.wait([
      synthesizeSegment(segments[0]),
      synthesizeSegment(segments[1]),
    ]);
    
    // Start aggressive prefetch for remaining segments
    _startPrefetch(segments.skip(2), prefetchWindow: 3);
  }
  
  @override
  EngineConfig getConfig(DeviceTier tier) {
    // Kokoro-specific tuning
    return EngineConfig(
      prefetchWindowSegments: tier == DeviceTier.flagship ? 3 : 2,
      maxConcurrentSynthesis: tier == DeviceTier.flagship ? 2 : 1,
      preloadOnOpen: true,  // Always warm up session
      coldStartSegments: 2,  // Pre-synthesize 2 segments
    );
  }
}
```

**Expected Buffering**: 0 seconds (100% elimination)

**Timeline**: 1 week implementation + 1 week testing

#### Scenario B: RTF 1.0-1.5x (Borderline) ⚠️

**Strategy**: Hybrid approach with extended pre-synthesis

```dart
class KokoroHybridSynthesis extends SmartSynthesisManager {
  @override
  Future<void> prepareForPlayback(Book book, int startPosition) async {
    final segments = segmentChapter(book, startPosition);
    
    // Calculate how many segments to pre-synthesize based on RTF
    final rtf = await _measureRTF();
    final preloadCount = (rtf * 3).ceil();  // RTF 1.2 → 4 segments
    
    developer.log('📊 Kokoro RTF: $rtf, pre-loading $preloadCount segments');
    
    // Pre-synthesize multiple segments sequentially
    for (var i = 0; i < preloadCount && i < segments.length; i++) {
      await synthesizeSegment(segments[i]);
      _notifyProgress(i + 1, preloadCount);
    }
    
    // Start cautious prefetch (single-threaded due to RTF)
    _startPrefetch(segments.skip(preloadCount), 
                   prefetchWindow: 1,
                   maxConcurrent: 1);
  }
}
```

**UI Experience**:
```dart
// Show progress bar during pre-synthesis
Widget buildPreparingUI(int current, int total) {
  return Column(
    children: [
      Text('Preparing Kokoro audio for smooth playback...'),
      LinearProgressIndicator(value: current / total),
      Text('$current of $total segments ready'),
      Text('Estimated wait: ${_estimateWait(total - current)}'),
    ],
  );
}
```

**Expected Buffering**: <5 seconds (95% reduction)

**Trade-off**: User waits 30-60 seconds before playback starts, but then smooth

#### Scenario C: RTF > 1.5x (Too Slow) ❌

**Strategy**: Full chapter pre-synthesis workflow

```dart
class KokoroChapterPreSynthesis {
  Future<void> preSynthesizeChapter(
    Book book, 
    int chapterIndex,
    {Function(int, int)? onProgress}
  ) async {
    final segments = segmentChapter(book, chapterIndex);
    developer.log('🔄 Pre-synthesizing ${segments.length} segments...');
    
    // Show UI: "Preparing chapter for offline listening"
    for (var i = 0; i < segments.length; i++) {
      await synthesizeSegment(segments[i]);
      await cacheSegment(segments[i]);
      onProgress?.call(i + 1, segments.length);
    }
    
    developer.log('✅ Chapter ${chapterIndex + 1} ready for playback');
  }
  
  // User workflow:
  // 1. Open book
  // 2. Select chapter
  // 3. Tap "Prepare Chapter" button
  // 4. Wait 5-10 minutes while chapter synthesizes
  // 5. Play with 0 buffering (all cached)
}
```

**UI Design**:
```dart
Widget buildChapterActions(Chapter chapter) {
  return Row(
    children: [
      // Show synthesis status
      if (chapter.isSynthesized)
        IconButton(
          icon: Icon(Icons.play_arrow, color: Colors.green),
          onPressed: () => playChapter(chapter),
          tooltip: 'Play (Ready)',
        )
      else
        IconButton(
          icon: Icon(Icons.download, color: Colors.orange),
          onPressed: () => preSynthesizeChapter(chapter),
          tooltip: 'Prepare for offline playback',
        ),
      
      // Show progress if synthesizing
      if (chapter.isSynthesizing)
        CircularProgressIndicator(value: chapter.synthesisProgress),
    ],
  );
}
```

**Expected Buffering**: 0 seconds (but requires pre-synthesis)

**Trade-off**: Not suitable for real-time playback, but works for planned listening

---

### Phase 4: Fallback - Recommend Against Kokoro (If All Else Fails)

**If optimization fails to achieve RTF < 1.0**:

#### 4.1 Update Voice Selection UI

```dart
class VoiceQualityIndicator extends StatelessWidget {
  final Voice voice;
  
  @override
  Widget build(BuildContext context) {
    final rtf = voice.measuredRTF ?? voice.expectedRTF;
    final isRealTime = rtf < 1.0;
    
    return ListTile(
      title: Text(voice.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(voice.description),
          SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isRealTime ? Icons.check_circle : Icons.warning,
                color: isRealTime ? Colors.green : Colors.orange,
                size: 16,
              ),
              SizedBox(width: 4),
              Text(
                isRealTime 
                  ? 'Real-time playback' 
                  : 'Requires pre-synthesis',
                style: TextStyle(
                  fontSize: 12,
                  color: isRealTime ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: voice.isDownloaded 
        ? Icon(Icons.check_circle, color: Colors.green)
        : IconButton(
            icon: Icon(Icons.download),
            onPressed: () => downloadVoice(voice),
          ),
    );
  }
}
```

#### 4.2 Add Warning When Selecting Kokoro

```dart
Future<void> selectVoice(Voice voice) async {
  if (voice.expectedRTF > 1.5) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ Performance Warning'),
        content: Text(
          'Kokoro produces very high-quality audio but is slower than '
          'real-time on most devices. This means you\'ll need to wait '
          'for audio synthesis before each chapter.\n\n'
          'For immediate playback, consider Supertonic or Piper voices.\n\n'
          'Do you want to continue with Kokoro?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Choose Different Voice'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Use Kokoro Anyway'),
          ),
        ],
      ),
    );
    
    if (proceed != true) return;
  }
  
  // Proceed with voice selection
  await _setVoice(voice);
}
```

#### 4.3 Documentation Update

Add to `README.md`:

```markdown
## Voice Performance Guide

| Voice | Quality | Speed | Real-Time | Recommended For |
|-------|---------|-------|-----------|-----------------|
| Supertonic | Excellent | Very Fast | ✅ Yes | General use, instant playback |
| Piper | Good | Fast | ✅ Yes | Balanced quality/speed |
| Kokoro | Outstanding | Slow | ❌ No | Audiophiles, pre-planned listening |

### Kokoro Voice Notes

Kokoro produces the highest audio quality but requires **pre-synthesis** of chapters 
before playback. This means:

✅ **Best for**:
- Offline/airplane listening (prepare chapters in advance)
- Audiobook archiving (synthesize entire book overnight)
- Users who prioritize quality over convenience

❌ **Not ideal for**:
- Spontaneous reading (want to start immediately)
- Sampling/browsing books (switching chapters frequently)
- Low-storage devices (requires caching entire chapters)

**Performance**: Synthesis takes approximately 2-3x longer than the audio duration. 
A 10-minute chapter may take 20-30 minutes to prepare.
```

---

## 4. Implementation Roadmap

### Week 1: Deep Analysis
- [ ] Implement detailed profiling (phonemization, inference, postprocessing)
- [ ] Investigate phoneme warnings and correlation with slow segments
- [ ] Memory and GC analysis
- [ ] Deliverable: Performance report with bottleneck identification

### Week 2-3: Model Optimization
- [ ] Test alternative quantization levels (float32, float16)
- [ ] Optimize ONNX Runtime configuration (threads, graph optimization)
- [ ] Implement session warm-up and reuse
- [ ] Test GPU/NPU execution providers if available
- [ ] Deliverable: Optimized Kokoro adapter with measured RTF improvement

### Week 4: Decision Point
**If RTF < 1.0**: 
- [ ] Implement standard pre-synthesis strategy
- [ ] Configure aggressive prefetch for Kokoro
- [ ] Test on multiple device tiers

**If RTF 1.0-1.5x**:
- [ ] Implement hybrid pre-synthesis (4-6 segments)
- [ ] Add progress UI for pre-load phase
- [ ] Test user experience with extended wait time

**If RTF > 1.5x**:
- [ ] Implement chapter pre-synthesis workflow
- [ ] Update voice selection UI with warnings
- [ ] Add "Prepare Chapter" feature
- [ ] Document Kokoro as "pre-synthesis only" voice

### Week 5-6: Testing and Polish
- [ ] Test across flagship/mid-range/budget devices
- [ ] Measure battery impact of optimization strategies
- [ ] User acceptance testing (UAT) for pre-synthesis workflows
- [ ] Update documentation with final recommendations

---

## 5. Success Criteria

### Target Metrics (by Scenario)

#### Scenario A: Real-Time Achieved (RTF < 1.0)
- ✅ **Buffering**: 0 seconds (100% elimination)
- ✅ **First Segment**: <3 seconds wait
- ✅ **User Experience**: Identical to Supertonic/Piper
- ✅ **Device Support**: Flagship and mid-range devices

#### Scenario B: Borderline (RTF 1.0-1.5x)
- ✅ **Buffering**: <5 seconds total (95% reduction)
- ⚠️ **Pre-load Wait**: 30-60 seconds before playback
- ⚠️ **User Experience**: "Preparing audio..." progress bar
- ⚠️ **Device Support**: Flagship devices only

#### Scenario C: Pre-Synthesis Only (RTF > 1.5x)
- ✅ **Buffering**: 0 seconds (after pre-synthesis)
- ❌ **Pre-synthesis Time**: 2-3x audio duration
- ❌ **User Experience**: "Prepare chapter before listening"
- ❌ **Device Support**: All devices (offline workflow)

### Minimum Acceptable Outcome

Even if real-time is unachievable:
- ✅ Kokoro remains available for users who prioritize quality
- ✅ Clear communication about performance trade-offs
- ✅ Smooth pre-synthesis workflow with progress indication
- ✅ Recommendation system guides users to appropriate voices

---

## 6. Risk Assessment

### High Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| RTF never reaches <1.0 | High (70%) | High | Accept and implement Scenario C |
| ONNX optimization has minimal impact | Medium (50%) | High | Focus on alternative quantization |
| GPU/NPU providers unavailable on Android | High (80%) | Medium | Optimize CPU inference path |
| User frustration with slow synthesis | Medium (40%) | Medium | Clear warnings and voice recommendations |

### Medium Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Float32 model not available | Medium (40%) | Medium | Work with Kokoro maintainers for model export |
| Native implementation too complex | Low (20%) | Medium | Stick with Flutter ONNX, accept performance limit |
| Pre-synthesis fills up device storage | Medium (50%) | Low | Implement cache size limits and LRU eviction |

---

## 7. Alternative Approaches

### 7.1 Hybrid Voice Strategy

**Concept**: Use different voices for different scenarios

```dart
class AdaptiveVoiceSelector {
  Voice selectVoiceForScenario(ReadingScenario scenario, Voice userPreference) {
    // If user wants Kokoro but needs instant playback, switch temporarily
    if (userPreference.name == 'Kokoro' && scenario.requiresRealTime) {
      return Voice.supertonic;  // Fast fallback
    }
    
    return userPreference;
  }
}

enum ReadingScenario {
  browsing,        // Sampling chapters → Use Supertonic
  commuting,       // Real-time listening → Use Piper
  archiving,       // Pre-synthesize entire book → Use Kokoro
}
```

### 7.2 Cloud Synthesis Option

**Concept**: Offer cloud-based Kokoro synthesis for instant delivery

```dart
class CloudKokoroSynthesis {
  // Send text to cloud API, receive pre-synthesized audio
  Future<AudioSegment> synthesizeViaCloud(String text) async {
    final response = await http.post(
      Uri.parse('https://api.example.com/kokoro/synthesize'),
      body: json.encode({'text': text, 'voice': 'kokoro_af'}),
    );
    
    return AudioSegment.fromBytes(response.bodyBytes);
  }
}
```

**Trade-offs**:
- ✅ Instant real-time performance
- ❌ Requires internet connection
- ❌ Privacy concerns (text sent to server)
- ❌ Subscription cost for API usage

### 7.3 Model Distillation

**Concept**: Train a smaller, faster "Kokoro-Lite" model

**Process**:
1. Use full Kokoro model to generate training data
2. Train smaller student model to mimic Kokoro's output
3. Deploy distilled model with ~0.5-0.8x RTF

**Trade-offs**:
- ✅ Faster inference, maintains quality
- ❌ Requires ML expertise and training resources
- ❌ Quality degradation vs. full Kokoro
- ❌ Months of development time

---

## 8. Comparison with Other Engines

### Lessons Learned from Supertonic and Piper

| Strategy | Supertonic | Piper | Kokoro |
|----------|------------|-------|--------|
| Pre-synthesize first segment | ✅ Eliminates 100% buffering | ✅ Eliminates 75% buffering | ⚠️ Insufficient (RTF too high) |
| Aggressive prefetch | ✅ Works (RTF 0.26x) | ✅ Works (RTF 0.38x) | ❌ Falls behind (RTF 2.76x) |
| Cold start optimization | ✅ Minor impact (already fast) | ✅ Minor impact (already fast) | ⚠️ Critical (21s first segment) |
| Multi-threaded synthesis | ✅ 2-3x parallel safe | ✅ 2x parallel safe | ❌ Might worsen performance |

**Key Insight**: Kokoro cannot use the same strategies as faster engines. It requires fundamentally different approach focused on **optimization first, prefetch second**.

---

## 9. User Communication Strategy

### In-App Messaging

**Voice Selection Screen**:
```
🎤 Kokoro AF
   High-quality voice with natural prosody
   
   ⚠️ Performance Note:
   Kokoro requires audio preparation before playback.
   Recommended for offline listening and audiobook archiving.
   
   For instant playback, try Supertonic or Piper voices.
   
   [Download] [Learn More]
```

**First-Time Kokoro Usage**:
```
Welcome to Kokoro!

You've selected a voice that prioritizes audio quality over speed.
Before you can start listening, we'll need to prepare the audio
for this chapter.

This is a one-time process per chapter and takes approximately
2-3 minutes for a 10-minute chapter.

Prepared audio is cached for instant replay.

[Prepare Now] [Switch Voice] [Don't Show Again]
```

### Documentation

Update `README.md` and in-app help:

```markdown
## Choosing the Right Voice

### Supertonic (Recommended for Most Users)
- **Speed**: Very Fast (RTF 0.26x)
- **Quality**: Excellent
- **Buffering**: None
- **Best for**: General audiobook listening, instant playback

### Piper
- **Speed**: Fast (RTF 0.38x)
- **Quality**: Good
- **Buffering**: None
- **Best for**: Balanced quality and speed

### Kokoro (Advanced Users)
- **Speed**: Slow (RTF 2.76x)
- **Quality**: Outstanding
- **Buffering**: None (after pre-synthesis)
- **Best for**: Audiophiles, offline listening, archival

**Important**: Kokoro requires chapters to be prepared before listening.
This process takes 2-3x longer than the audio duration but produces
the highest quality TTS output available.
```

---

## 10. Future Improvements

### 10.1 Intelligent Chapter Pre-Synthesis

```dart
class PredictivePreSynthesis {
  // Pre-synthesize next chapter while user listens to current chapter
  Future<void> backgroundPreSynthesis(Book book, int currentChapter) async {
    if (currentChapter + 1 < book.chapters.length) {
      developer.log('📚 Pre-synthesizing next chapter in background...');
      
      await preSynthesizeChapter(
        book, 
        currentChapter + 1,
        priority: Priority.low,  // Don't interfere with playback
      );
      
      developer.log('✅ Next chapter ready');
    }
  }
}
```

**Benefit**: By the time user finishes current chapter, next is ready

### 10.2 Overnight Batch Synthesis

```dart
class ScheduledSynthesis {
  // Schedule full book synthesis when device is charging + idle
  Future<void> scheduleBookSynthesis(Book book, {DateTime? startTime}) async {
    final workManager = await WorkManager.getInstance();
    
    await workManager.registerPeriodicTask(
      'synthesis_${book.id}',
      'book_synthesis',
      constraints: Constraints(
        requiresCharging: true,
        requiresDeviceIdle: true,
      ),
      inputData: {'bookId': book.id},
    );
    
    developer.log('📅 Scheduled synthesis for ${book.title}');
  }
}
```

**Benefit**: Users wake up to fully synthesized books

### 10.3 Cloud Fallback (Optional)

```dart
class HybridKokoroEngine {
  Future<AudioSegment> synthesize(String text) async {
    // Try local synthesis first
    try {
      final audio = await _localSynthesis(text);
      return audio;
    } catch (e) {
      // Fall back to cloud if local is too slow or fails
      if (await _isCloudAvailable()) {
        return await _cloudSynthesis(text);
      }
      rethrow;
    }
  }
}
```

**Benefit**: Best of both worlds (privacy + performance)

---

## 11. Conclusion

### Expected Outcome

**Most Likely**: Kokoro will NOT achieve real-time performance (RTF < 1.0) through optimization alone, due to fundamental model complexity. However, it can still provide value through:

1. **Pre-synthesis workflow**: Users prepare chapters in advance for high-quality offline listening
2. **Background synthesis**: Next chapters prepare automatically during playback
3. **Clear expectations**: Users understand trade-offs and choose appropriate voices

### Development Philosophy

**Accept the Trade-off**: Kokoro is a quality-over-speed voice, and that's okay. Not every voice needs to support real-time playback. The key is:

- ✅ Transparent communication about performance
- ✅ Smooth pre-synthesis experience
- ✅ Recommendation system guiding users to appropriate voices
- ✅ Fallback options for users who need instant playback

### Success Definition

This plan succeeds if:
1. We achieve maximum possible RTF reduction through optimization
2. We provide excellent UX for Kokoro's pre-synthesis workflow
3. Users understand when to use Kokoro vs. other voices
4. No user is surprised or frustrated by Kokoro's performance

### Next Steps

1. **Week 1**: Execute deep performance analysis (Phase 1)
2. **Week 2-3**: Implement optimization strategies (Phase 2)
3. **Week 4**: Make go/no-go decision based on achieved RTF
4. **Week 5-6**: Implement appropriate workflow (Scenario A/B/C)

---

## Appendix: Kokoro Benchmark Raw Data

```
Total time: 1054 seconds
Total segments: 45
Average time per segment: 23.4 seconds
RTF: 2.76x

Segment-by-segment breakdown:
Segment 1: 21.4s (238 chars)
Segment 2: 25.8s (203 chars)
Segment 3: 16.9s (218 chars)
Segment 4: 14.7s (231 chars)
Segment 5: 8.5s (228 chars)  ← Fastest
Segment 6: 26.1s (224 chars)
Segment 7: 15.3s (221 chars)
Segment 8: 19.2s (215 chars)
Segment 9: 11.4s (213 chars)
Segment 10: 20.2s (223 chars)
[... continued ...]
Segment 28: 52.0s (221 chars)  ← Slowest (outlier)
[... continued ...]
Segment 45: 17.3s (207 chars)

Unknown phoneme warnings: ~15 occurrences of \\U+025a and \\U+0329
```

### Key Observations

1. **No correlation between text length and synthesis time**:
   - Segment 5 (228 chars): 8.5s
   - Segment 28 (221 chars): 52s
   → Suggests specific phoneme patterns cause slowdowns

2. **High variability**: 6.1x difference between fastest and slowest segments

3. **Cold start**: First segment 21.4s vs average 23.4s (not exceptional)

4. **Warning frequency**: Unknown phonemes appear in ~33% of segments

---

**Document Version**: 1.0  
**Last Updated**: 2024-01-03  
**Status**: Ready for Review  
**Estimated Implementation Time**: 6 weeks (with decision points)
