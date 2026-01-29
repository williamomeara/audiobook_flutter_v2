# iOS Supertonic Integration Plan

## Problem Statement

The current iOS Supertonic implementation incorrectly uses `sherpa-onnx` VITS wrapper (expecting a single `model.onnx`), but Supertonic actually uses a **4-stage multi-model pipeline** requiring 4 separate ONNX/CoreML models:

1. **Duration Predictor** (`duration_predictor.onnx`) - estimates audio length
2. **Text Encoder** (`text_encoder.onnx`) - produces linguistic embedding
3. **Vector Estimator** (`vector_estimator.onnx`) - diffusion-based denoising (iterative)
4. **Vocoder** (`vocoder.onnx`) - latent vectors → audio samples

## Reference Implementations

### 1. Official ONNX Runtime Implementation
- **Repository**: [supertone-inc/supertonic](https://github.com/supertone-inc/supertonic)
- **iOS Demo**: `ios/ExampleiOSApp/TTSService.swift`
- **Dependency**: `onnxruntime-objc` CocoaPod/SPM
- **Key Files**:
  - `OnnxRuntimeBindings` module for Swift ↔ ONNX Runtime
  - `TextToSpeech.swift` for the 4-stage pipeline

### 2. CoreML Optimized Implementation (Recommended)
- **Repository**: [Nooder/supertonic-2-coreml](https://github.com/Nooder/supertonic-2-coreml)
- **iOS Demo**: `supertonic2-coreml-ios-test/TTSService.swift` (45KB, complete implementation)
- **HuggingFace Models**: [Nooder/supertonic-2-coreml](https://huggingface.co/Nooder/supertonic-2-coreml)
- **No external dependencies** - uses native CoreML framework
- **Variants available**:
  - `coreml_int8` - fast, lower fidelity
  - `coreml_compressed` - smaller memory (linear8)
  - `coreml_ios18_int8_both` - fastest on iOS 18+

## Recommended Approach: CoreML

CoreML is preferred over ONNX Runtime for iOS because:
1. **No external dependencies** - uses Apple's native framework
2. **Better Neural Engine support** - optimized for Apple silicon
3. **Quantized variants** - smaller memory, faster inference
4. **iOS 18 optimization** - specific models for latest devices

## Implementation Plan

### Phase 1: Prepare CoreML Models (1-2 hours) ✅ COMPLETED

- [x] **1.1** Download CoreML models from HuggingFace
  - Downloaded to `.staging/supertonic-ios/` using `git lfs pull`
  
- [x] **1.2** Select appropriate variant
  - Selected `coreml_ios18_int8_both/` for iOS 18+ (fastest, ~72MB)
  
- [x] **1.3** Required model files (per variant):
  - `duration_predictor_mlprogram.mlpackage` (1.2MB)
  - `text_encoder_mlprogram.mlpackage` (14MB)
  - `vector_estimator_mlprogram.mlpackage` (33MB)
  - `vocoder_mlprogram.mlpackage` (24MB)
  
- [x] **1.4** Required resource files:
  - `voice_styles/` (M1-M5.json, F1-F5.json) - 10 voice styles
  - `embeddings/` (char_embedder_dp, char_embedder_te)
  - `onnx/unicode_indexer.json`
  - `onnx/tts.json`

**Assets Location:** 
`packages/platform_ios_tts/ios/Assets/supertonic_coreml/` (77MB total)

**Reference Implementation:**
`docs/features/ios-supertonic-integration/TTSServiceReference.swift`
- Original: https://github.com/Nooder/supertonic-2-coreml/blob/main/supertonic2-coreml-ios-test/TTSService.swift

### Phase 2: Update Download Manifest (30 min) ✅ COMPLETED

**Decision: Bundle with app instead of on-demand download**

For iOS, the CoreML models are bundled directly with the app binary instead of downloaded at runtime. This is simpler and provides offline-first capability.

- [x] **2.1** Updated `platform_ios_tts.podspec`
  - Added `s.resources = 'Assets/supertonic_coreml/**/*'`
  - Models will be copied to app bundle at build time
  
- [x] **2.2** Platform-specific approach
  - **Android**: Downloads ONNX models at runtime (existing behavior)
  - **iOS**: CoreML models bundled with app (77MB added to app size)

**Note**: To reduce app size in future, could implement on-demand download:
1. Host CoreML models on GitHub releases or CloudFlare R2
2. Add iOS-specific entries to voices_manifest.json
3. Modify Dart adapter to check `Platform.isIOS` for different core paths

### Phase 3: Rewrite SupertonicTtsService for CoreML (4-6 hours) ✅ COMPLETED

- [x] **3.1** Created `SupertonicCoreMLInference.swift`
  - New file: `packages/platform_ios_tts/ios/Classes/inference/SupertonicCoreMLInference.swift`
  - Ported TTSService from [Nooder/supertonic-2-coreml](https://github.com/Nooder/supertonic-2-coreml)
  - Key components:
    - `loadFromBundle()` - loads models, embeddings, unicode indexer, config
    - `loadModelsConcurrently()` - loads 4 CoreML models in parallel
    - `runDurationPredictor()` - stage 1
    - `runTextEncoder()` - stage 2
    - `runVectorEstimator()` - stage 3 (iterative denoising)
    - `runVocoder()` - stage 4
    - 600+ lines of Swift

- [x] **3.2** Updated `SupertonicTtsService.swift`
  - Replaced `SupertonicSherpaInference` with `SupertonicCoreMLInference`
  - Updated `loadCore()` to detect `__BUNDLED_COREML__` marker
  - Calls `coremlInference.loadFromBundle()` for iOS bundled models
  - Updated `synthesize()` to use CoreML 4-stage pipeline

- [x] **3.3** Voice styles handled in CoreMLInference
  - Loads voice style JSON files (M1.json, F1.json, etc.) from bundle
  - Maps voice IDs via speakerId (0-4 → M1-M5, 5-9 → F1-F5)
  - Caches loaded voice styles for reuse

### Phase 4: Update Xcode Project Configuration (30 min) ✅ COMPLETED

- [x] **4.1** sherpa-onnx dependency kept
  - Cannot remove - still needed by Piper and Kokoro TTS services
  - SupertonicSherpaInference.swift kept for reference (unused by SupertonicTtsService now)
  
- [x] **4.2** CoreML model bundles configured via podspec
  - `s.resources = 'Assets/supertonic_coreml/**/*'` already added in Phase 2
  - Assets verified at `packages/platform_ios_tts/ios/Assets/supertonic_coreml/`
  - Models will be bundled with app at build time via pod install

### Phase 5: Update Dart Adapter (1 hour) ✅ COMPLETED IN PHASE 2

- [x] **5.1** Updated `supertonic_adapter.dart` for iOS
  - Added `_isIosBundled` flag: `bool get _isIosBundled => Platform.isIOS;`
  - `probe()` returns `EngineAvailability.available` for iOS (line 54-57)
  - `ensureCoreReady()` passes `'__BUNDLED_COREML__'` marker for iOS (line 72-79)
  - `checkVoiceReady()` returns `VoiceReadyState.voiceReady` for iOS (line 128-135)
  
- [x] **5.2** iOS-specific behavior
  - No download required for iOS - models bundled with app
  - CoreML models loaded from app bundle on first synthesis
  - Voice styles loaded from bundled JSON files

### Phase 6: Testing and Validation (2 hours)

**Code Review Verification (Completed):**
- ✅ All required Swift files exist:
  - `SupertonicCoreMLInference.swift` (650+ lines) - CoreML 4-stage pipeline
  - `SupertonicTtsService.swift` (135 lines) - Service wrapper
  - `TtsServiceProtocol.swift` - TtsError, VoiceInfo, SynthesisCounter
  - `AudioConverter.swift` - writeWav, durationMs
- ✅ All required CoreML assets bundled using `resource_bundles` in podspec:
  - `SupertonicDurationPredictor.bundle`
  - `SupertonicTextEncoder.bundle`
  - `SupertonicVectorEstimator.bundle`
  - `SupertonicVocoder.bundle`
  - `SupertonicResources.bundle` (embeddings, config, voice styles)
- ✅ Podspec updated with separate resource_bundles for each model
- ✅ Dart adapter updated with iOS-specific `__BUNDLED_COREML__` handling

**Bug Fixes Applied:**
- Fixed `.mlpackage` bundle conflicts by using separate `resource_bundles`
- Fixed Float16 availability check for iOS 16+
- Fixed `readScalar()` to handle Float16 dataType (CoreML int8 models use Float16)

**Manual Testing Results:**
- [x] **6.1** Test model loading
  - ✅ All 4 CoreML models load from separate bundles
  - ✅ Model compilation takes ~30 seconds on first load
  - ✅ `maxTextLen=300, latentDim=144, latentLenMax=288`

- [x] **6.2** Test synthesis
  - ✅ Developer menu synthesis works
  - ✅ Voice M1 tested successfully
  - ✅ 51 character text produced ~2.4s audio in 0.61s (RTF ~0.25)
  - [ ] Test all voice styles (M1-M5, F1-F5)
  - [ ] Test in book playback context

- [ ] **6.3** Performance testing
  - Measure RTF (Real-Time Factor)
  - Compare CPU vs GPU vs All compute units

## Alternative Approach: ONNX Runtime

If CoreML proves problematic, use ONNX Runtime:

### Dependencies
- Add `onnxruntime-objc` via CocoaPods or SPM:
  ```ruby
  pod 'onnxruntime-objc', '~> 1.19'
  ```

### Implementation
- Port from [supertone-inc/supertonic/ios](https://github.com/supertone-inc/supertonic/tree/main/ios)
- Use `OnnxRuntimeBindings` module
- Same 4-stage pipeline, but using ORTSession instead of MLModel

## File Changes Required

| File | Action | Description |
|------|--------|-------------|
| `SupertonicSherpaInference.swift` | Replace | New CoreML inference implementation |
| `SupertonicTtsService.swift` | Rewrite | Use CoreML models instead of VITS |
| `supertonic_adapter.dart` | Update | iOS-specific model paths |
| `voices_manifest.json` | Update | Add CoreML model downloads |
| `ios/Podfile` | Possibly | Add onnxruntime-objc if using ONNX |

## Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Prepare Models | 1-2 hours | None |
| Phase 2: Update Manifest | 30 min | Phase 1 |
| Phase 3: Rewrite Service | 4-6 hours | Phase 1 |
| Phase 4: Xcode Config | 30 min | Phase 3 |
| Phase 5: Dart Adapter | 1 hour | Phase 3 |
| Phase 6: Testing | 2 hours | All phases |

**Total: ~10-12 hours**

## Quick Workaround (Temporary)

If immediate fixes are needed, disable Supertonic on iOS:

1. In `supertonic_adapter.dart`, add iOS platform check:
   ```dart
   @override
   Future<void> ensureCoreReady(CoreSelector selector) async {
     if (Platform.isIOS) {
       throw VoiceNotAvailableException(
         'supertonic',
         'Supertonic is not yet supported on iOS. Use Piper or Kokoro.',
       );
     }
     // ... existing Android logic
   }
   ```

2. Hide Supertonic voices from iOS voice picker.

## Resources

- [supertone-inc/supertonic](https://github.com/supertone-inc/supertonic) - Official repo
- [Nooder/supertonic-2-coreml](https://github.com/Nooder/supertonic-2-coreml) - CoreML port
- [HuggingFace: Nooder/supertonic-2-coreml](https://huggingface.co/Nooder/supertonic-2-coreml) - Model downloads
- [HuggingFace: Supertone/supertonic-2](https://huggingface.co/Supertone/supertonic-2) - Original ONNX models

---

## Lessons Learned

### Architecture Differences (Critical Discovery)

The root cause of the iOS Supertonic failure was a fundamental architecture mismatch:

| Platform | Inference Engine | Model Format | Approach |
|----------|------------------|--------------|----------|
| **Android** | Custom JNI/ONNX Runtime | 4 ONNX models | `supertonic_native.cpp` (1400+ lines C++) |
| **iOS (OLD - WRONG)** | sherpa-onnx VITS wrapper | Expected single `model.onnx` | SupertonicSherpaInference.swift |
| **iOS (NEW - CORRECT)** | Native CoreML | 4 CoreML .mlpackage models | SupertonicCoreMLInference.swift |

**Lesson**: Supertonic is NOT a VITS model. It uses a 4-stage diffusion-based pipeline:
1. Duration Predictor → estimates audio length
2. Text Encoder → linguistic embedding
3. Vector Estimator → diffusion denoising (iterative, ~20 steps)
4. Vocoder → latent → audio waveform

### CoreML vs ONNX Runtime Trade-offs

| Factor | CoreML | ONNX Runtime |
|--------|--------|--------------|
| **Dependencies** | None (native) | `onnxruntime-objc` pod |
| **Neural Engine** | Full support | Limited support |
| **Quantization** | int8, compressed variants | fp32 or custom |
| **Model format** | .mlpackage (folder) | .onnx (single file) |
| **iOS 18 optimization** | Dedicated variants | N/A |

**Decision**: CoreML was chosen for better Neural Engine support and no external dependencies.

### Bundle vs Download Trade-off

| Approach | Pros | Cons |
|----------|------|------|
| **Bundle with app** | Offline-first, simpler, faster startup | +77MB app size |
| **Download on demand** | Smaller app install | Requires hosting, network handling |

**Decision**: Bundle for simplicity. Can optimize later with on-demand download if app size becomes an issue.

### Voice ID Mapping

Supertonic uses speaker IDs (0-9) that map to voice files:
- speakerId 0-4 → M1.json, M2.json, M3.json, M4.json, M5.json (male voices)
- speakerId 5-9 → F1.json, F2.json, F3.json, F4.json, F5.json (female voices)

Voice IDs in the app (e.g., `supertonic_m4`) encode the speaker ID. The CoreML inference extracts this and loads the corresponding style JSON.

### Diffusion Steps Trade-off

Vector Estimator uses iterative diffusion denoising:
- **More steps** (40): Higher quality, slower
- **Fewer steps** (8-20): Faster, slightly lower quality
- **Default**: 20 steps (good balance)

The implementation allows runtime configuration via `speed` parameter adjustment.

### MLMultiArray Memory Layout

CoreML MLMultiArray data can be non-contiguous. The `getContiguousData()` helper ensures safe access:
```swift
func getContiguousData() -> [Float] {
    // Creates a contiguous copy if needed
    // Handles both contiguous and strided layouts
}
```

### iOS 18 Specific Models

The `coreml_ios18_int8_both` variant is optimized for iOS 18's enhanced Neural Engine:
- Uses int8 quantization for speed
- Targets Apple A17/M3+ chips
- Not backward compatible with iOS 15-17 (would need fallback)

---

## Testing Checklist (Phase 6)

Before merging, verify:

- [ ] `pod install` succeeds without errors
- [ ] Xcode project opens and builds without Swift errors
- [ ] CoreML models are copied to app bundle (check `Runner.app/Contents/Resources/`)
- [ ] App launches on iOS device
- [ ] Supertonic voice appears in voice picker
- [ ] Test synthesis with short text (< 50 chars)
- [ ] Test synthesis with medium text (100-300 chars)
- [ ] Test all 10 voice styles (M1-M5, F1-F5)
- [ ] Verify audio quality is acceptable
- [ ] Check memory usage during synthesis
- [ ] Measure RTF (Real-Time Factor)

---

## Files Changed Summary

| File | Action | Lines Changed |
|------|--------|---------------|
| `packages/platform_ios_tts/ios/Classes/inference/SupertonicCoreMLInference.swift` | **Created** | 600+ lines |
| `packages/platform_ios_tts/ios/Classes/engines/SupertonicTtsService.swift` | **Rewritten** | ~130 lines |
| `packages/tts_engines/lib/src/adapters/supertonic_adapter.dart` | **Modified** | ~20 lines added |
| `packages/platform_ios_tts/ios/platform_ios_tts.podspec` | **Modified** | 2 lines added |
| `packages/platform_ios_tts/ios/Assets/supertonic_coreml/` | **Created** | 77MB assets |
| `docs/features/ios-supertonic-integration/PLAN.md` | **Created** | This document |

---

## Next Steps (Post-Testing)

1. **Commit & Push**: Once tests pass, commit with descriptive message
2. **App Size Review**: Check if 77MB CoreML bundle is acceptable
3. **iOS 15-17 Fallback**: Consider adding older CoreML variant for backward compatibility
4. **On-Demand Download**: Implement if app size needs reduction
5. **Performance Tuning**: Adjust diffusion steps if needed
