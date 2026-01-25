# ONNX-Compatible TTS Models Research (2026)

**Date:** 2026-01-25  
**Author:** AI Analysis  
**Status:** Research Complete

## Executive Summary

This document evaluates the latest TTS models that support ONNX export for potential integration into our mobile audiobook app. Several promising options exist with varying trade-offs between quality, size, and features.

## Quick Comparison Table

| Model | ONNX Size | RAM (Est.) | Quality | Mobile Ready | Languages | Key Feature |
|-------|-----------|------------|---------|--------------|-----------|-------------|
| **Our Current: Kokoro** | ~147 MB | ~300 MB | Very Good | ✅ Yes | EN | Balanced |
| **Our Current: Piper** | ~60 MB | ~100 MB | Good | ✅ Yes | EN | Tiny, fast |
| **Our Current: Supertonic** | ~245 MB | ~400 MB | Excellent | ✅ Yes | EN | Best quality |
| **VibeVoice-0.5B** | ~500 MB+ | ~1+ GB | Excellent | ⚠️ Maybe | EN/ZH | Multi-speaker |
| **CosyVoice2-0.5B** | ~245-400 MB | ~500 MB+ | Excellent | ⚠️ Maybe | Multi | Emotion control |
| **MeloTTS** | ~160 MB | ~200 MB | Good | ✅ Yes | Multi | VITS-based |
| **XTTS-v2** | ~200-400 MB | ~500 MB | Excellent | ⚠️ Maybe | 13+ | Voice cloning |

---

## Detailed Analysis

### 1. VibeVoice (Microsoft) - **Promising for Future**

**Overview:** Microsoft's newest open-source TTS, released 2026. LLM-based architecture with impressive long-form generation.

**Model Variants:**
| Variant | Parameters | Purpose | Mobile Viability |
|---------|-----------|---------|------------------|
| VibeVoice-Realtime-0.5B | 500M | Real-time, low latency | Possible on high-end |
| VibeVoice-1.5B | 1.5B | Long-form, multi-speaker | Desktop/server only |
| VibeVoice-7B | 7B | Highest quality | Server only |

**Technical Specs (0.5B version):**
- Latency: <300ms first packet
- Context: Up to 8K tokens (8-10 minutes)
- Multi-speaker: Up to 4 speakers
- Speech tokenization: 7.5 Hz (efficient)

**Pros:**
- Long-form generation (up to 90 minutes with larger models)
- Multi-speaker conversations
- Microsoft backing, active development
- ONNX export available

**Cons:**
- 500M parameters is still large for budget Android
- Estimated 1+ GB RAM requirement
- Limited language support (EN, ZH)
- New model, less community testing

**Recommendation:** Monitor development. May be viable for flagship devices in future.

---

### 2. CosyVoice2 (FunAudioLLM/Alibaba) - **Strong Candidate**

**Overview:** Alibaba's streaming TTS with fine-grained emotion and dialect control. Official ONNX export support.

**Model Sizes:**
| Model | Size | Notes |
|-------|------|-------|
| flow_fp32.onnx | ~490 MB | Full precision |
| flow_fp16.onnx | ~245 MB | Half precision |
| flow_hift_combined_fp16.onnx | ~395-410 MB | Combined pipeline |

**Technical Specs:**
- Latency: ~150ms ultra-low latency
- Languages: Chinese, English, Japanese, Korean
- MOS Score: 5.4+ (industry leading)
- Streaming: Yes, built-in

**Pros:**
- Excellent quality (MOS 5.4+)
- Official ONNX export with documentation
- Multi-language support
- Emotion and dialect control
- Low latency streaming

**Cons:**
- 245-400 MB model size (similar to Supertonic)
- Estimated 500 MB+ RAM usage
- Complex multi-model pipeline (flow + HiFT)
- Primarily optimized for Chinese

**Recommendation:** Good candidate for multi-language feature. Evaluate if size fits our budget device targets.

---

### 3. MeloTTS (MyShell) - **Best for Immediate Integration**

**Overview:** VITS-based multilingual TTS, lightweight and well-suited for mobile.

**Model Sizes:**
| Format | Size |
|--------|------|
| PyTorch | ~190 MB |
| ONNX | ~160 MB |
| INT8 Quantized | ~80-100 MB (estimated) |

**Technical Specs:**
- Architecture: VITS-based (non-autoregressive)
- Languages: English, Chinese, Spanish, and more
- Mixed-language: Yes
- CPU Optimized: Yes

**Pros:**
- Small ONNX model (~160 MB)
- Architecture similar to our current engines (VITS-based)
- Active community with ONNX export tools
- Good multilingual support
- CPU-optimized, low latency
- Proven mobile deployments

**Cons:**
- Quality slightly below LLM-based models
- Fewer voice options than premium models
- No voice cloning

**Recommendation:** **Best immediate candidate.** Similar architecture to Piper/Kokoro, proven ONNX export, reasonable size.

---

### 4. XTTS-v2 (Coqui) - **Future Voice Cloning Option**

**Overview:** Popular zero-shot voice cloning TTS with multilingual support.

**Technical Specs:**
- Languages: 13+ languages
- Voice Cloning: Yes (zero-shot)
- ONNX: Community exports available

**Model Size:** 200-400 MB (varies by optimization)

**Pros:**
- Zero-shot voice cloning from short samples
- 13+ languages
- Large community, well-tested
- Expressive prosody

**Cons:**
- Larger memory footprint (~500 MB RAM)
- Voice cloning requires reference audio processing
- ONNX export requires community tools (not official)
- More complex integration

**Recommendation:** Consider for future "clone your own voice" feature.

---

## Integration Priority Recommendations

### Tier 1: Immediate (1-2 months)

**MeloTTS**
- Why: Architecture matches our existing engines, proven ONNX export, reasonable size
- Effort: Low-medium (similar to adding Piper)
- Benefit: Multi-language support (EN, ZH, ES, etc.)

### Tier 2: Short-term (3-6 months)

**CosyVoice2-0.5B**
- Why: Official ONNX support, excellent quality, emotion control
- Effort: Medium (new pipeline architecture)
- Benefit: Premium quality multi-language, streaming

### Tier 3: Long-term (6-12 months)

**VibeVoice-Realtime-0.5B**
- Why: Microsoft backing, long-form potential
- Effort: High (LLM-based architecture)
- Benefit: Multi-speaker audiobook reading

**XTTS-v2**
- Why: Voice cloning feature
- Effort: High (complex voice extraction pipeline)
- Benefit: Users can clone their own voices

---

## Comparison with Our Current Engines

### Size Comparison
```
Our Engines (proven, working):
├── Piper:      ~60 MB  ████████
├── Kokoro:     ~147 MB ████████████████████
└── Supertonic: ~245 MB ████████████████████████████████

New Candidates:
├── MeloTTS:    ~160 MB █████████████████████ ← Good fit
├── CosyVoice2: ~245 MB ████████████████████████████████ ← Same as Supertonic
└── VibeVoice:  ~500 MB+ ████████████████████████████████████████████████████ ← Large
```

### Quality vs Size Trade-off

| Engine | Quality (1-10) | Size (MB) | Quality/MB Ratio |
|--------|---------------|-----------|------------------|
| Piper | 6 | 60 | 0.10 |
| Kokoro | 8 | 147 | 0.054 |
| Supertonic | 9 | 245 | 0.037 |
| MeloTTS | 7 | 160 | 0.044 |
| CosyVoice2 | 9 | 245 | 0.037 |
| VibeVoice-0.5B | 9 | 500+ | 0.018 |

---

## Technical Considerations

### ONNX Runtime Compatibility

All recommended models work with ONNX Runtime, which we already use. Key considerations:

1. **Graph Optimization**: Enable ONNX Runtime graph optimizations
2. **Quantization**: INT8 quantization can reduce size by 50%
3. **NNAPI**: Android NNAPI acceleration available for supported ops
4. **CoreML**: iOS CoreML conversion possible for some models

### Memory Budget

Our target devices: Budget Android (3-4 GB total RAM)
- Available for app: ~1 GB max
- Current peak (Supertonic): ~400 MB
- Safety margin needed: ~200 MB for OS/other apps

**Safe new model limit: ~400 MB RAM**

---

## Action Items

- [ ] Test MeloTTS ONNX export on Android device
- [ ] Benchmark MeloTTS inference speed vs Piper
- [ ] Evaluate MeloTTS audio quality for audiobook use case
- [ ] Research CosyVoice2 ONNX integration complexity
- [ ] Monitor VibeVoice-0.5B community mobile deployments

## References

- [MeloTTS GitHub](https://github.com/myshell-ai/MeloTTS)
- [MeloTTS ONNX Export](https://github.com/TangLinJie/MeloTTS-ONNX-EXPORT)
- [CosyVoice2 GitHub](https://github.com/FunAudioLLM/CosyVoice)
- [CosyVoice2 ONNX](https://huggingface.co/Lourdle/CosyVoice2-0.5B_ONNX)
- [VibeVoice GitHub](https://microsoft.github.io/VibeVoice/)
- [XTTS-v2 / Coqui](https://github.com/coqui-ai/TTS)
- [ONNX Runtime Mobile](https://onnxruntime.ai/docs/tutorials/mobile/)
