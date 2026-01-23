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

### Phase 3: Rewrite SupertonicTtsService for CoreML (4-6 hours)

- [ ] **3.1** Replace `SupertonicSherpaInference.swift` with `SupertonicCoreMLInference.swift`
  - Port TTSService from [Nooder/supertonic-2-coreml](https://github.com/Nooder/supertonic-2-coreml)
  - Key components:
    - `loadResources()` - loads embeddings, unicode indexer, config
    - `loadModelsConcurrently()` - loads 4 CoreML models in parallel
    - `runDurationPredictor()` - stage 1
    - `runTextEncoder()` - stage 2
    - `runVectorEstimator()` - stage 3 (iterative denoising)
    - `runVocoder()` - stage 4

- [ ] **3.2** Update `SupertonicTtsService.swift`
  - Replace `SupertonicSherpaInference` with `SupertonicCoreMLInference`
  - Update `loadCore()` to:
    1. Locate CoreML `.mlpackage` directories
    2. Load all 4 models
    3. Load embeddings and configs
  - Update `synthesize()` to use the 4-stage pipeline

- [ ] **3.3** Handle voice styles
  - Load voice style JSON files (M1.json, F1.json, M2.json, etc.)
  - Map voice IDs (supertonic_m1 → M1, supertonic_f3 → F3)

### Phase 4: Update Xcode Project Configuration (30 min)

- [ ] **4.1** Remove unused dependencies
  - Remove sherpa-onnx VITS dependency (if not used by Piper/Kokoro)
  
- [ ] **4.2** Add CoreML model bundles to project
  - Configure `.mlpackage` folders as bundle resources
  - Ensure models are included in app binary

### Phase 5: Update Dart Adapter (1 hour)

- [ ] **5.1** Update `supertonic_adapter.dart`
  - Modify `ensureCoreReady()` to check for iOS-specific CoreML models
  - Update path logic: `{coreDir}/supertonic/coreml_ios18/` or similar
  
- [ ] **5.2** Update `_initEngine()` and `_loadVoice()`
  - CoreML models don't need separate "voice loading"
  - Voice styles are loaded from JSON files

### Phase 6: Testing and Validation (2 hours)

- [ ] **6.1** Test model loading
  - Verify all 4 CoreML models load without errors
  - Check memory usage

- [ ] **6.2** Test synthesis
  - Test with various text inputs
  - Test all voice styles (M1-M5, F1-F5)
  - Test language selection (en, ko, es, pt, fr)

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
