# Feature: Extreme audio compression with EnCodec/Lyra neural codecs

## Overview

We currently use AAC at 64kbps for cache compression (~0.48 MB/min). For users with limited storage, we could achieve dramatically better compression using neural audio codecs.

## Compression Comparison

| Format/Codec | Bitrate | Space/Min | Notes |
|--------------|---------|-----------|-------|
| Current (AAC) | 64 kbps | ~0.48 MB | Good quality |
| HE-AAC v2 | 16-24 kbps | ~0.15 MB | 3x smaller, "phone call" quality |
| Opus | 6-12 kbps | ~0.06 MB | 8x smaller, good for speech |
| **EnCodec/Lyra** | 3-6 kbps | ~0.02 MB | **24x smaller**, neural reconstruction |

## Neural Codec Approach

Meta's [EnCodec](https://github.com/facebookresearch/encodec) and Google's [Lyra](https://github.com/google/lyra) use neural networks to:
1. Encode audio into compact "tokens" (like a script of sounds)
2. Decode tokens back to audio using a small AI model at playback time

### Potential Benefits
- **24x smaller** than current AAC: 10-hour audiobook = ~12 MB instead of ~300 MB
- Speech-optimized (perfect for TTS audio)
- Open-source models available

### Why This is Feasible for Us

We already have ONNX Runtime set up for TTS inference:
- `packages/platform_android_tts/` - Android ONNX integration
- Kokoro/Piper/Supertonic models already use ONNX

### Implementation Approach

1. **Export EnCodec ONNX models**
   - Encoder: WAV → tokens (~10 MB model)
   - Decoder: tokens → WAV (~10 MB model)

2. **Integrate with existing cache system**
   - Store `.enc` files instead of `.m4a`
   - Decode on-demand before playback
   - Could also stream decode for gapless playback

3. **User setting**
   - "Compression level": Standard (AAC) vs Ultra (EnCodec)
   - Trade-off: Higher CPU during compression/playback

### Challenges

- **Encoding time**: Neural encoding is slower than AAC (~2-5x realtime on mobile)
- **Decoding latency**: Need to buffer ahead for smooth playback
- **Model size**: +20MB app size for encoder+decoder models
- **Battery**: More CPU work during playback

### Prior Art

- WhatsApp uses Lyra for voice messages
- Discord uses Opus neural (similar tech)
- [encodec-jax](https://github.com/CPUFronz/encodec-jax) - Minimal EnCodec implementation

## Proposed Phases

### Phase 1: Research
- [ ] Test EnCodec ONNX export
- [ ] Benchmark encoding/decoding speed on Android
- [ ] Measure quality at 6kbps for TTS audio

### Phase 2: Implementation
- [ ] Add encoder service using existing ONNX infrastructure
- [ ] Add decoder integration with playback
- [ ] Add settings toggle

### Phase 3: Polish
- [ ] Optimize decode latency for streaming playback
- [ ] Add migration path for existing caches

## Difficulty Assessment

**Medium-High difficulty** because:
1. ✅ ONNX infrastructure already exists (reduces complexity)
2. ⚠️ EnCodec model export to ONNX requires Python work
3. ⚠️ Decode latency needs careful tuning for smooth playback
4. ⚠️ Testing across device performance levels needed

**Estimated effort**: 2-3 weeks

## Related

- Current compression feature: `packages/tts_engines/lib/src/cache/aac_compression_service.dart`
- ONNX setup: `packages/platform_android_tts/android/src/main/kotlin/`
