# Qwen3-TTS Evaluation for Audiobook Flutter App

**Date:** 2026-01-25  
**Author:** AI Analysis  
**Status:** Research Complete

## Executive Summary

Qwen3-TTS is a powerful new TTS system from Alibaba's Qwen team, released January 2026. While it offers impressive features including multilingual support, voice cloning, and voice design, **it is NOT recommended for integration** into our mobile audiobook app due to significant resource requirements and architectural incompatibilities.

## Overview

### What is Qwen3-TTS?

Qwen3-TTS is a series of large language model (LLM)-based TTS systems featuring:
- **Voice Clone**: 3-second audio → custom voice
- **Voice Design**: Natural language descriptions → new voices
- **Custom Voices**: 9 premium pre-built voices
- **Multilingual**: 10 languages (Chinese, English, Japanese, Korean, German, French, Russian, Portuguese, Spanish, Italian)
- **Streaming**: Dual-track hybrid architecture with 97ms first-packet latency

### Model Variants

| Model | Size | Features | Use Case |
|-------|------|----------|----------|
| Qwen3-TTS-12Hz-0.6B-Base | 600M params | Voice clone | Smallest, basic features |
| Qwen3-TTS-12Hz-0.6B-CustomVoice | 600M params | 9 premium voices | Fixed voice set |
| Qwen3-TTS-12Hz-1.7B-Base | 1.7B params | Voice clone | Higher quality clone |
| Qwen3-TTS-12Hz-1.7B-CustomVoice | 1.7B params | 9 voices + instructions | Best custom voice |
| Qwen3-TTS-12Hz-1.7B-VoiceDesign | 1.7B params | Create voices via text | Most flexible |

## Technical Analysis

### Resource Requirements (Estimated)

| Configuration | GPU VRAM | System RAM | Storage |
|--------------|----------|------------|---------|
| 0.6B FP16 | 2-3 GB | 4+ GB | ~1.2 GB |
| 0.6B INT8 | 1-2 GB | 2-3 GB | ~0.6 GB |
| 1.7B FP16 | 5-6 GB | 6+ GB | ~3.4 GB |
| 1.7B INT8 | 2-3 GB | 3-4 GB | ~1.7 GB |

### Comparison with Current Engines

| Engine | Model Size | RAM Usage | Speed (RTF) | Quality |
|--------|-----------|-----------|-------------|---------|
| **Piper** | ~60 MB | ~100 MB | 0.1-0.3x | Good |
| **Kokoro** | ~147 MB | ~300 MB | 0.3-0.5x | Very Good |
| **Supertonic** | ~245 MB | ~400 MB | 0.2-0.4x | Excellent |
| **Qwen3-TTS 0.6B** | ~600 MB | 2+ GB | Unknown | Unknown |
| **Qwen3-TTS 1.7B** | ~1.7 GB | 4+ GB | Unknown | Expected Excellent |

## Pros & Cons

### ✅ Pros

1. **Excellent Multilingual Support**: 10 languages vs our English-only engines
2. **Voice Cloning**: Clone any voice from 3 seconds of audio
3. **Voice Design**: Create custom voices via text descriptions
4. **High Quality**: LLM-based architecture produces natural prosody
5. **Streaming Support**: 97ms first-packet latency
6. **Open Source**: Apache 2.0 license, weights available on HuggingFace
7. **Active Development**: Released January 2026, actively maintained

### ❌ Cons

1. **Massive Resource Requirements**
   - 0.6B model: ~2 GB RAM minimum (vs our current ~400 MB max)
   - 1.7B model: ~4-6 GB RAM (exceeds most mobile devices)
   - Our target devices: Budget Android phones with 3-4 GB total RAM

2. **No ONNX Export (Yet)**
   - Our app uses ONNX Runtime for cross-platform inference
   - Qwen3-TTS requires PyTorch/Transformers or vLLM
   - Would require significant architecture changes

3. **GPU Dependency**
   - Designed for CUDA GPUs with FlashAttention
   - Mobile GPUs via ONNX Runtime are very different
   - No Android NNAPI or iOS CoreML support

4. **Model Architecture Incompatibility**
   - LLM-based (autoregressive transformer)
   - Our engines are VITS/FastSpeech2-based (non-autoregressive)
   - Completely different inference patterns

5. **Battery Impact**
   - LLM inference is extremely power-hungry
   - Our engines are optimized for mobile efficiency
   - Would likely drain battery 5-10x faster

6. **Download Size**
   - 0.6B model: ~600 MB - 1.2 GB download
   - 1.7B model: ~1.7 - 3.4 GB download
   - Our largest current download: ~245 MB (Supertonic)

7. **Latency Concerns**
   - While streaming is supported, total synthesis time unknown
   - Mobile CPU inference could be prohibitively slow

## Implementation Feasibility

### Required Work (If We Proceeded)

1. **ONNX Conversion Pipeline**
   - Convert Qwen3-TTS to ONNX format
   - Likely requires custom export script
   - May lose features like streaming

2. **Quantization**
   - INT8 quantization mandatory for mobile
   - INT4 possibly needed for budget devices
   - Quality degradation unknown

3. **Architecture Changes**
   - New native adapter for Android
   - New CoreML adapter for iOS
   - Memory management overhaul

4. **Testing & Optimization**
   - Extensive device compatibility testing
   - Performance tuning for each platform
   - Battery consumption optimization

### Effort Estimate: 3-6 months of dedicated work

## Recommendation

**Do NOT integrate Qwen3-TTS at this time.**

### Reasons

1. **Resource mismatch**: Our app targets budget devices; Qwen3-TTS targets GPUs
2. **No mobile path**: No ONNX/CoreML/NNAPI support exists
3. **Massive engineering**: Would require months of work with uncertain results
4. **Existing engines sufficient**: Kokoro + Supertonic already provide excellent quality

### Alternative Strategies

1. **Monitor for Mobile Variant**: Alibaba may release a smaller, mobile-optimized version
2. **Server-Side Option**: Consider cloud API for users who want voice cloning
3. **Evaluate in 6-12 Months**: If ONNX export becomes available
4. **Focus on Kokoro/Supertonic**: Continue improving our existing high-quality engines

## Future Considerations

Qwen3-TTS could become viable if:
- [ ] Official ONNX export is released
- [ ] A ~100-200M parameter variant is released
- [ ] Community creates mobile-optimized forks
- [ ] Mobile devices gain significantly more RAM (8+ GB standard)

## References

- [Qwen3-TTS GitHub Repository](https://github.com/QwenLM/Qwen3-TTS)
- [HuggingFace Models](https://huggingface.co/collections/Qwen/qwen3-tts)
- [Technical Report (arXiv)](https://arxiv.org/abs/2601.15621)
- [Qwen3-TTS Blog Post](https://qwen.ai/blog?id=qwen3tts-0115)
