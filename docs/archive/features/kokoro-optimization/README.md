# Kokoro TTS Optimization Project

## Executive Summary

This project focuses on optimizing the Kokoro TTS engine to achieve real-time or near-real-time synthesis performance. Currently Kokoro has an RTF (Real-Time Factor) of 2.76x, meaning it synthesizes audio slower than real-time, causing significant buffering during playback.

**Current State**: 
- RTF: 2.76x (synthesis is 2.76x slower than audio duration)
- First Segment: 21.4s synthesis time
- Total Buffering: 15,351s for a 383s test (every segment buffers)

**Goal**: Achieve RTF < 1.0 (ideally < 0.8) through optimization, or develop a pre-synthesis workflow with excellent UX.

**Timeline**: Estimated 4-6 weeks (dedicated project)

---

## Why a Separate Project?

Kokoro optimization is fundamentally different from the smart-audio-synth feature:

1. **High Risk**: Optimization may require breaking and rebuilding Kokoro integration
2. **Deep Technical**: Requires ONNX Runtime profiling, native code changes, possible model retraining
3. **Uncertain Outcome**: May not achieve real-time performance regardless of optimization
4. **Independent Testing**: Needs isolated testing to avoid affecting other voices

---

## Problem Analysis

### Current Performance (from benchmarks)

```
Engine: Kokoro AF
RTF: 2.76x (SLOWER than real-time)
First Segment: 21.4s
Average Segment: 23.4s
Total Buffering: 15,351s (every segment buffers)
Buffering Events: 45 (100% of segments)
```

### Root Cause Hypotheses

1. **Phoneme Processing**: Kokoro logs show phoneme warnings that may indicate slow processing
2. **Model Quantization**: Current int8 quantization may have issues
3. **ONNX Runtime Configuration**: Thread count, graph optimization, execution providers
4. **Memory/GC**: Dart/JNI boundary overhead, memory allocation patterns
5. **Model Size**: Kokoro model may be too large for efficient mobile inference

---

## Investigation Plan

### Phase 1: Deep Profiling (Week 1)

1. **Component Timing Analysis**
   - Measure phonemization time
   - Measure ONNX inference time
   - Measure audio postprocessing time
   - Identify which component is the bottleneck

2. **Phoneme Warning Investigation**
   - Analyze frequency of unknown phoneme warnings
   - Correlate warnings with synthesis slowdown
   - Test with different text samples

3. **Memory Profiling**
   - JNI boundary overhead
   - GC pauses during synthesis
   - Memory allocation patterns

### Phase 2: Optimization Attempts (Weeks 2-3)

1. **ONNX Runtime Tuning**
   - Thread count optimization
   - Graph optimization levels
   - Session options tuning
   - Warm-up session patterns

2. **Quantization Testing**
   - Test float32 model (if available)
   - Test float16 model
   - Compare quality vs performance

3. **Parallel Synthesis**
   - Test parallel inference
   - Measure speedup factor
   - Memory constraints

4. **Native Implementation**
   - Evaluate C++ implementation overhead
   - Consider JNI optimization

### Phase 3: Strategy Decision (Week 4)

Based on optimization results, choose one of three strategies:

**Scenario A: RTF < 1.0 Achieved**
- Use standard smart-audio-synth approach
- Pre-synthesize 1-2 segments, prefetch works

**Scenario B: RTF 1.0-1.5x (Borderline)**
- Extended pre-synthesis workflow
- Pre-load 4-6 segments with progress UI
- Moderate wait before playback

**Scenario C: RTF > 1.5x (Current State)**
- Full chapter pre-synthesis workflow
- "Prepare Chapter" button in UI
- 5-10 minute preparation per chapter
- Zero buffering after preparation

### Phase 4: Implementation (Weeks 5-6)

Implement the chosen strategy with:
- Clear user-facing UX
- Progress indicators
- Voice selection warnings
- Settings integration

---

## Success Criteria

| Scenario | RTF | User Experience | Implementation |
|----------|-----|-----------------|----------------|
| A (Best) | < 1.0 | Instant playback like Supertonic/Piper | Standard smart-synth |
| B (Good) | 1.0-1.5 | 30-60s wait with progress, then smooth | Hybrid pre-synthesis |
| C (Acceptable) | > 1.5 | "Prepare Chapter" workflow, then smooth | Full pre-synthesis |

---

## Files to Create

- `PROFILING_RESULTS.md` - Benchmark and profiling data
- `OPTIMIZATION_LOG.md` - Record of optimization attempts
- `ONNX_TUNING.md` - ONNX Runtime configuration experiments
- `PHONEME_ANALYSIS.md` - Phoneme warning investigation
- `STRATEGY_DECISION.md` - Final decision and rationale
- `IMPLEMENTATION.md` - Implementation details for chosen strategy

---

## Dependencies

This project depends on:
- `packages/platform_android_tts/lib/src/kokoro/` - Native Kokoro integration
- `packages/tts_engines/lib/src/adapters/kokoro_adapter.dart` - Dart adapter
- ONNX Runtime Android libraries

---

## Related Documentation

- `../smart-audio-synth/ENGINE_KOKORO_PLAN.md` - Original Kokoro optimization notes
- `../smart-audio-synth/RTF_ANALYSIS.md` - RTF benchmarks for all engines

---

**Status**: Planning  
**Priority**: High (Kokoro is currently unusable for real-time playback)  
**Estimated Effort**: 4-6 weeks
