# Kokoro TTS Performance Optimization Plan

## Current Performance (2026-01-06)

- **Test text**: "Hello, this is a test of the text to speech engine." (52 chars)
- **Audio duration**: ~2.88 seconds
- **Synthesis time**: ~2.88 seconds
- **Real-Time Factor (RTF)**: ~1.0 (just real-time)

### Comparison with Piper
- **Piper RTF**: 0.34x (3x faster than real-time)
- **Kokoro RTF**: 1.0x (real-time)
- Kokoro is ~3x slower than Piper per second of audio

## Model Details

- **Model**: `kokoro-multi-lang-v1_0` (~350MB, includes voices.bin)
- **Sample Rate**: 24,000 Hz
- **Engine**: sherpa-onnx OfflineTts with Kokoro backend
- **Architecture**: Multi-lingual Kokoro with voice embeddings (53 speakers)

## Optimization Strategies

### 1. Thread Count Tuning (Low effort, Medium impact)

**Current**: `numThreads = 2`

**Action**: Benchmark with different thread counts based on device CPU cores.

```kotlin
val cpuCores = Runtime.getRuntime().availableProcessors()
val optimalThreads = when {
    cpuCores >= 8 -> 4
    cpuCores >= 4 -> 3
    else -> 2
}
```

**Expected improvement**: 10-30% on high-core devices

### 2. Segment Pre-computation / Pipelining (Medium effort, High impact)

**Problem**: Current synthesis is blocking - user waits for entire sentence.

**Solution**: Segment text and pipeline synthesis with playback.

```
Segment 1: [synth] -> [play] 
Segment 2:          [synth] -> [play]
Segment 3:                    [synth] -> [play]
```

**Implementation**:
1. Split text at sentence/clause boundaries
2. Start synthesis of segment N+1 while playing segment N
3. Use audio queue to buffer synthesized segments

**Expected improvement**: Perceived latency drops from full sentence time to first segment time (~50-70% perceived improvement)

### 3. Voice-Specific Model Caching (Low effort, Low impact)

**Problem**: Model initialization takes ~1-2 seconds on first call.

**Current behavior**: Model loaded on first synthesis, kept in memory.

**Improvement**: Pre-warm model when user selects Kokoro voice.

**Expected improvement**: Eliminates first-call latency spike

### 4. English-Only Model Option (Medium effort, High impact)

**Current model**: `kokoro-multi-lang-v1_0.tar.bz2` (~350MB)
- Supports: English, Chinese, Japanese, French, etc.
- Large embedding space

**Alternative**: `kokoro-int8-en-v0_19.tar.bz2` (103MB)
- English only
- Smaller, potentially faster

**Action**: 
1. Add English-only model as download option
2. Benchmark speed difference

**Expected improvement**: 15-25% faster synthesis, 44MB smaller download

### 5. NNAPI/GPU Acceleration (High effort, High impact)

**Problem**: Kokoro runs on CPU only with ONNX Runtime.

**Solutions**:
- **NNAPI**: Android Neural Networks API for hardware acceleration
- **Qualcomm QNN**: Snapdragon NPU acceleration
- **GPU**: OpenCL/Vulkan compute shaders

**Sherpa-onnx support**: Limited - NNAPI requires specific build options.

**Expected improvement**: 2-4x faster on supported hardware

### 6. Model Quantization Improvements (High effort, Medium impact)

**Current**: INT8 quantization

**Options**:
- **INT4 quantization**: Smaller, faster, slightly lower quality
- **Mixed precision**: FP16 compute with INT8 weights

**Note**: Requires retraining/re-quantizing the model

**Expected improvement**: 20-40% faster for INT4

## Recommended Priority Order

| Priority | Strategy | Effort | Impact | Timeline |
|----------|----------|--------|--------|----------|
| 1 | Segment pipelining | Medium | High | 1-2 weeks |
| 2 | Thread count tuning | Low | Medium | 1 day |
| 3 | English-only model | Medium | High | 3-5 days |
| 4 | Pre-warming | Low | Low | 1 day |
| 5 | NNAPI exploration | High | High | 2-4 weeks |
| 6 | INT4 quantization | High | Medium | Research |

## Success Metrics

- **Target RTF**: 0.5x (2x faster than real-time)
- **First-word latency**: < 500ms
- **Memory usage**: < 300MB peak

## Notes

- Kokoro's higher quality justifies slower speed for non-real-time use cases
- Pipelining is the most impactful change for perceived performance
- Consider fallback to Piper for real-time preview, Kokoro for final synthesis
