# Kokoro TTS Optimization Plan

## Overview

This document outlines a plan to upgrade Kokoro TTS implementation to use platform-optimized models for better performance on iOS (CoreML/MLX) and Android (ONNX int8 quantized).

## Current State

### What We Have
- **iOS**: Uses `sherpa-onnx` with CPU provider for Kokoro inference
- **Android**: Uses `sherpa-onnx` with full-precision ONNX model (~350MB)
- **Model**: `kokoro-multi-lang-v1_0.tar.bz2` from k2-fsa/sherpa-onnx releases

### Current Performance Issues
- iOS: CPU inference is slower and uses more battery than ANE/CoreML
- Android: Full-precision model (~350MB) is larger than necessary for int8 devices
- Both: Not utilizing hardware accelerators (NPU/ANE)

## Target Architecture

### iOS: MLX Swift + CoreML
- **Library**: [mlalma/kokoro-ios](https://github.com/mlalma/kokoro-ios)
- **Performance**: ~3.3x faster than real-time on iPhone 13 Pro
- **Dependencies**:
  - MLX Swift framework
  - MisakiSwift (G2P processor)
  - MLXUtilsLibrary

### Android: ONNX int8 Quantized
- **Reference**: [puff-dayo/Kokoro-82M-Android](https://github.com/puff-dayo/Kokoro-82M-Android)
- **Model Size**: ~90MB (int8) vs ~350MB (full precision)
- **Source**: [kokoro-onnx int8 models](https://github.com/thewh1teagle/kokoro-onnx)

### Cross-Platform Reference
- **Expo/React Native**: [isaiahbjork/expo-kokoro-onnx](https://github.com/isaiahbjork/expo-kokoro-onnx)
- Useful for model management patterns and voice handling

---

## Implementation Plan

### Phase 1: Android ONNX int8 Optimization
**Estimated Effort**: 1-2 days
**Risk**: Low (model format compatible with existing code)

#### Tasks
- [ ] **1.1** Update manifest to point to int8 quantized model
  - Change model URL from `kokoro-multi-lang-v1_0.tar.bz2` to int8 version
  - Update file size in manifest
  
- [ ] **1.2** Verify sherpa-onnx compatibility with int8 model
  - Test that `KokoroSherpaInference` works with int8 model
  - Benchmark performance difference
  
- [ ] **1.3** Update model loading logic if needed
  - Check if model filename changes (model.onnx vs model.int8.onnx)
  - Update `findModelFile()` in KokoroTtsService.kt

#### Model Sources (int8)
- **Direct int8**: https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0
- **HuggingFace**: https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX (model_quantized.onnx ~92MB)

---

### Phase 2: iOS MLX/CoreML Integration
**Estimated Effort**: 3-5 days
**Risk**: Medium-High (significant code changes required)

#### Option A: MLX Swift (Recommended)
Use mlalma/kokoro-ios which provides a complete Swift implementation.

##### Tasks
- [ ] **2.1** Add KokoroSwift SPM dependency to platform_ios_tts
  ```swift
  dependencies: [
      .package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.0")
  ]
  ```

- [ ] **2.2** Create `KokoroMLXInference.swift` class
  - Mirror API of existing `KokoroSherpaInference.swift`
  - Implement: `loadModel()`, `synthesize()`, `unload()`
  
- [ ] **2.3** Update `KokoroTtsService.swift`
  - Add toggle between sherpa-onnx and MLX backends
  - Use MLX for Kokoro, keep sherpa for Piper
  
- [ ] **2.4** Model file management
  - Download MLX-format model (safetensors)
  - Voice style embeddings handling
  - G2P (MisakiSwift) integration

- [ ] **2.5** Update manifest for iOS
  - Add iOS-specific core with MLX model URL
  - Voice embeddings file separate from model

##### Model Requirements (MLX)
- Model file: ~150MB safetensors format
- Voice styles: Voice embeddings array
- G2P: MisakiSwift handles tokenization

#### Option B: CoreML (mattmireles/kokoro-coreml)
More complex due to two-stage pipeline architecture.

##### Considerations
- Requires Duration Model + HAR Decoder (two models)
- Fixed-size buckets (3s, 10s, 45s)
- Client-side alignment matrix building in Swift
- More code to maintain

---

### Phase 3: Platform-Specific Download Architecture
**Estimated Effort**: 2-3 days

#### Current State
The manifest already supports platform filtering via `"platform": "android"|"ios"` field:
- `ManifestService._isPlatformMatch()` filters cores by platform
- `_resolvePlatformCore()` maps generic core IDs to platform-specific versions
- Supertonic already has separate `supertonic_core_v1` (Android) and `supertonic_core_ios_v1` (iOS)

#### Tasks
- [ ] **3.1** Add platform-specific Kokoro cores to manifest
  ```json
  {
    "id": "kokoro_core_android_v1",
    "engineType": "kokoro",
    "displayName": "Kokoro TTS Core (Android int8)",
    "url": "https://.../kokoro-int8.tar.gz",
    "platform": "android"
  },
  {
    "id": "kokoro_core_ios_v1", 
    "engineType": "kokoro",
    "displayName": "Kokoro TTS Core (iOS MLX)",
    "url": "https://.../kokoro-mlx.tar.gz",
    "platform": "ios"
  }
  ```

- [ ] **3.2** Update voice coreRequirements for platform independence
  - Voices should reference generic `kokoro_core_v1`
  - ManifestService resolves to platform-specific at download time

- [ ] **3.3** Consider separate voice embedding formats
  - Android: Combined `voices.bin` (sherpa-onnx format)
  - iOS: MLX-compatible voice style tensors

- [ ] **3.4** Platform-specific download URLs
  ```
  Android: int8 ONNX (~90MB) + voices.bin
  iOS: MLX safetensors (~150MB) + voice styles
  ```

#### Manifest Structure Update
```json
{
  "cores": [
    {
      "id": "kokoro_core_android_v1",
      "engineType": "kokoro",
      "platform": "android",
      "url": "https://github.com/.../kokoro-android-int8.tar.gz",
      "sizeBytes": 95000000
    },
    {
      "id": "kokoro_core_ios_v1",
      "engineType": "kokoro", 
      "platform": "ios",
      "url": "https://github.com/.../kokoro-ios-mlx.tar.gz",
      "sizeBytes": 160000000
    }
  ],
  "voices": [
    {
      "id": "kokoro_af_alloy",
      "engineId": "kokoro",
      "coreRequirements": ["kokoro_core_android_v1", "kokoro_core_ios_v1"],
      "speakerId": 0
    }
  ]
}
```

#### Code Changes
- `ManifestService`: Already handles platform filtering ✓
- `GranularDownloadManager`: May need updates for MLX model extraction
- `KokoroTtsService` (both platforms): Detect model format and use appropriate inference

---

### Phase 4: Voice Management Updates
**Estimated Effort**: 1-2 days

#### Tasks
- [ ] **4.1** Update voice manifest structure
  - Separate voice embeddings from core model
  - Platform-specific voice file formats
  
- [ ] **4.2** Voice preview regeneration
  - Delete incorrect voice previews
  - Generate new previews with correct speaker IDs
  
- [ ] **4.3** Voice selection improvements
  - Individual voice embedding files (like HuggingFace format)
  - On-demand voice download vs bundled

---

### Phase 5: Testing & Validation
**Estimated Effort**: 1-2 days

#### Tasks
- [ ] **5.1** Unit tests for new inference code
- [ ] **5.2** Performance benchmarking
  - RTF (Real-Time Factor) measurements
  - Memory usage comparison
  - Battery impact testing
- [ ] **5.3** Voice quality validation
  - All 53 voices produce correct output
  - Speaker ID mapping verified

---

## File Changes Summary

### Android
```
packages/platform_android_tts/
├── android/src/main/kotlin/.../services/
│   └── KokoroTtsService.kt          # Minor updates for int8 model
├── android/src/main/kotlin/.../sherpa/
│   └── KokoroSherpaInference.kt     # No changes needed
```

### iOS
```
packages/platform_ios_tts/
├── Package.swift                     # Add KokoroSwift dependency
├── ios/Classes/
│   ├── engines/
│   │   └── KokoroTtsService.swift   # Backend selection logic
│   └── inference/
│       ├── KokoroSherpaInference.swift  # Existing (keep as fallback)
│       └── KokoroMLXInference.swift     # NEW: MLX-based inference
```

### Manifest
```
packages/downloads/lib/manifests/voices_manifest.json
# Update core URLs, add platform-specific cores
```

---

## Model URLs

### Android (int8 ONNX)
- **kokoro-onnx v1.0 int8**: https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v0_19-int8.onnx
- **Size**: ~80-90MB
- **Voices**: https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin

### iOS (MLX)
- **Model**: Requires conversion or use kokoro-ios compatible format
- **Reference**: https://github.com/mlalma/KokoroTestApp for model setup

---

## Decision Points

### Question 1: Keep sherpa-onnx as fallback?
**Recommendation**: Yes, for:
- Older iOS devices without MLX support
- Piper TTS (still needs sherpa-onnx)
- Development/debugging

### Question 2: Model download strategy?
**Options**:
1. **Separate downloads**: Different models per platform
2. **Universal model**: One model format (current approach)

**Recommendation**: Separate downloads for optimal performance

### Question 3: Voice embedding format?
**Options**:
1. **Combined voices.bin**: Current sherpa-onnx format
2. **Individual .bin files**: HuggingFace/kokoro-onnx format

**Recommendation**: Stay with combined voices.bin for compatibility, but support individual voices for future flexibility

---

## Success Metrics

| Metric | Current | Target (iOS) | Target (Android) |
|--------|---------|--------------|------------------|
| RTF | ~0.5 | ~0.3 | ~0.2-0.3 |
| Model Size | 350MB | 150MB | 90MB |
| Memory Peak | ~500MB | ~300MB | ~200MB |
| Battery Impact | High | Low (ANE) | Medium |

---

## References

### GitHub Repositories
- https://github.com/mlalma/kokoro-ios - Swift MLX implementation
- https://github.com/mlalma/KokoroTestApp - Example iOS app
- https://github.com/puff-dayo/Kokoro-82M-Android - Android demo (archived)
- https://github.com/isaiahbjork/expo-kokoro-onnx - React Native cross-platform
- https://github.com/thewh1teagle/kokoro-onnx - Int8 quantized models
- https://github.com/mattmireles/kokoro-coreml - CoreML conversion (complex)

### HuggingFace Models
- https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX
- https://huggingface.co/hexgrad/Kokoro-82M

### Documentation
- https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
- https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/kokoro-multi-lang-v1_0.html

---

## Appendix: Speaker ID Reference (kokoro-multi-lang-v1_0)

| Speaker ID | Voice Name | Type |
|------------|------------|------|
| 0 | af_alloy | US Female |
| 2 | af_bella | US Female |
| 6 | af_nicole | US Female |
| 9 | af_sarah | US Female |
| 10 | af_sky | US Female |
| 11 | am_adam | US Male |
| 16 | am_michael | US Male |
| 21 | bf_emma | British Female |
| 22 | bf_isabella | British Female |
| 26 | bm_george | British Male |
| 27 | bm_lewis | British Male |

Full mapping: See k2-fsa speaker ID documentation.
