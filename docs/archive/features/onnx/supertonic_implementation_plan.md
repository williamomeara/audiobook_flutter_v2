# Supertonic TTS Implementation Plan

## Executive Summary

Supertonic is a 4-stage ONNX TTS pipeline that requires raw ONNX Runtime inference (not sherpa-onnx). This document outlines the implementation strategy to integrate Supertonic without breaking existing Piper/Kokoro functionality.

## Phase 1 Research Notes (2026-01-06)

### Key Findings

#### 1. ONNX Runtime is Already Available
The sherpa-onnx AAR bundles `libonnxruntime.so` (16MB for arm64) with the standard ONNX Runtime C API:
- `OrtGetApiBase` - entry point to get the API function table
- `OrtSessionOptionsAppendExecutionProvider_CPU`
- `OrtSessionOptionsAppendExecutionProvider_Nnapi`

This is the **official Microsoft ONNX Runtime C API** - we can use it directly via JNI.

#### 2. No Library Conflicts Needed
Since we'll use the **same** `libonnxruntime.so` that sherpa-onnx bundles:
- No need for separate ONNX Runtime dependency
- No native library conflicts
- Shares memory pool with sherpa-onnx

#### 3. Supertonic Model Structure (from HuggingFace)
```
onnx/
├── text_encoder.onnx      (27MB)   - Text → embeddings
├── duration_predictor.onnx (1.5MB) - Embeddings → durations
├── vector_estimator.onnx  (132MB)  - Flow-matching denoising
├── vocoder.onnx           (101MB)  - Latent → audio
├── tts.json               (8KB)    - Model configuration
└── unicode_indexer.json   (262KB)  - Character → token mapping
```

Total: ~262MB

#### 4. JNI Approach
We'll create native C code that:
1. Uses `dlopen("libonnxruntime.so", RTLD_NOLOAD)` to get handle to already-loaded library
2. Retrieves `OrtGetApiBase` symbol with `dlsym()`
3. Uses standard ONNX Runtime C API for inference

#### 5. Sherpa-onnx C API Alternative
Alternatively, we could use `libsherpa-onnx-c-api.so` which provides simplified wrappers. However, it doesn't expose raw ONNX session creation - it only supports pre-defined model types (VITS, Kokoro, etc.).

## Current State

### What Works
- **Piper**: Uses sherpa-onnx's `OfflineTtsVitsModelConfig` - ✅ Working
- **Kokoro**: Uses sherpa-onnx's `OfflineTtsKokoroModelConfig` - ✅ Working

### What's Blocked for Supertonic
- Sherpa-onnx bundles `libonnxruntime.so` internally
- Adding `onnxruntime-android` Gradle dependency causes native library conflicts
- Current Supertonic implementation is a **stub** (generates silence)

## Supertonic Architecture

### Model Pipeline (4 ONNX files)
```
Text Input
    ↓
[Text Encoder]       → text_encoder.onnx (27MB)
    ↓
[Duration Predictor] → duration_predictor.onnx (1.5MB)
    ↓
[Vector Estimator]   → vector_estimator.onnx (132MB) - Flow-matching diffusion
    ↓
[Vocoder]            → vocoder.onnx (101MB)
    ↓
Audio Output (24kHz)
```

### Key Differentiators
- **No phonemization**: Works with raw Unicode text (NFKD normalized)
- **Multi-speaker**: Uses speaker style embeddings
- **Ultra-fast**: Claims 167x real-time on CPU
- **Total size**: ~262MB for full model

## Implementation Options

### Option 1: Raw JNI to sherpa-onnx's ONNX Runtime (Recommended)
**Complexity**: Medium | **Risk**: Low | **Effort**: 1-2 weeks

Sherpa-onnx bundles ONNX Runtime in `libsherpa-onnx-jni.so`. We can create JNI bindings to use the same ONNX Runtime for Supertonic inference.

**Steps**:
1. Create `SupertonicJni.kt` with native method declarations
2. Write `supertonic_jni.cpp` that links against sherpa-onnx's ONNX Runtime
3. Implement the 4-stage pipeline in native C++
4. Build and bundle with the app

**Pros**:
- No library conflicts
- Single ONNX Runtime instance
- Maximum performance

**Cons**:
- Requires C++ implementation
- Need to understand sherpa-onnx's internal ONNX API

### Option 2: Separate Process with onnxruntime-android
**Complexity**: High | **Risk**: Medium | **Effort**: 2-3 weeks

Run Supertonic in a separate Android process that loads `onnxruntime-android` independently.

**Steps**:
1. Create a new Android service in a separate process (`:supertonic`)
2. Add `onnxruntime-android` dependency with process isolation
3. Use Messenger/Binder IPC for synthesis requests
4. Serialize audio data back to main process

**Pros**:
- Uses official ONNX Runtime Android API
- Clean separation from sherpa-onnx

**Cons**:
- IPC overhead
- Memory duplication (two ONNX runtimes)
- Process management complexity

### Option 3: Wait for sherpa-onnx Supertonic Support
**Complexity**: Low | **Risk**: High (uncertain timeline) | **Effort**: N/A

Monitor sherpa-onnx project for Supertonic integration.

**Pros**:
- Zero development effort
- Native sherpa-onnx integration

**Cons**:
- Unknown timeline
- May never happen

### Option 4: Use Supertonic's Python/Node Wrapper with FFI
**Complexity**: High | **Risk**: High | **Effort**: 3-4 weeks

Bundle Python runtime and use Supertonic's official Python library.

**Pros**:
- Uses official Supertonic code

**Cons**:
- Massive app size increase
- Poor mobile performance
- Complex deployment

## Recommended Approach: Option 1 (JNI)

### Phase 1: Research & Prototype ✅ COMPLETED (2026-01-06)

**Status**: Infrastructure complete, builds successfully

**Completed**:
1. ✅ Analyzed sherpa-onnx ONNX Runtime API
   - Confirmed `OrtGetApiBase` available in bundled `libonnxruntime.so`
   - ONNX Runtime v17 API matches sherpa-onnx bundle
   - Dynamic linking via dlopen/dlsym works

2. ✅ Created JNI bridge
   - `packages/platform_android_tts/android/src/main/jni/supertonic_native.cpp`
   - `packages/platform_android_tts/android/src/main/jni/CMakeLists.txt`
   - `packages/platform_android_tts/android/src/main/kotlin/.../onnx/SupertonicNative.kt`

3. ✅ Build verified
   - `libsupertonic_native.so` built for all architectures (arm64, arm, x86, x86_64)
   - CMake integration with Gradle working
   - No conflicts with sherpa-onnx

4. ✅ Updated SupertonicInference.kt
   - Now uses JNI layer instead of stub
   - Proper error handling and logging

### Phase 2: Implement Pipeline ✅ COMPLETED (2026-01-06)

**Status**: Full ONNX inference pipeline implemented

**Completed**:
1. ✅ OrtApi struct definition with all required function pointers
   - CreateEnv, CreateSession, Run, CreateTensor, etc.
   - All Release functions for proper memory cleanup
   - Based on ONNX Runtime v17 API (matches sherpa-onnx)

2. ✅ Model loading and session management
   - Loads all 4 Supertonic models (text_encoder, duration_predictor, vector_estimator, vocoder)
   - Logs input/output names for debugging
   - Proper session options (optimization, threading)

3. ✅ Unicode tokenization
   - Parses `unicode_indexer.json` for character-to-token mapping
   - Full UTF-8 decoding support
   - Simple JSON parser (no external dependencies)

4. ✅ 4-stage inference pipeline
   - Text encoder: tokens → hidden states
   - Duration predictor: hidden states → durations
   - Vector estimator: hidden states + durations + speaker embedding → latent
   - Vocoder: latent → audio samples

5. ✅ Memory management
   - Uses ORT allocator for tensor memory (automatic cleanup)
   - Proper session and environment disposal

**Current Behavior**:
- Native library loads successfully
- Model files are verified on initialization
- All 4 ONNX models are loaded
- Input/output names are logged for debugging
- Synthesis runs the full pipeline

**Known Limitations**:
- Input/output tensor names are hardcoded (may not match actual model)
- Speaker embeddings use placeholder one-hot encoding
- Needs testing with actual Supertonic model files

**Next Steps** (Phase 3):
- Download and test with actual Supertonic model files
- Verify/fix input/output tensor names
- Load speaker style embeddings from voice_styles/*.json
- Add integration tests

### Phase 2: Implement Pipeline ✅ COMPLETED (2026-01-06) - Updated

**Additional work completed:**

6. ✅ Fixed unicode_indexer.json parser
   - Updated to parse JSON array format (not key-value)
   - Array index = Unicode codepoint, value = token index
   - Handles negative indices (-1 = invalid character)

7. ✅ Wired SupertonicTtsService to JNI bridge
   - `initEngine()` now calls `SupertonicNative.initialize()`
   - `synthesize()` now calls `SupertonicNative.synthesize()`
   - Added `floatToPcm16()` conversion for WAV output
   - Proper native resource cleanup on dispose

8. ✅ Updated voice manifest
   - Added all 10 voices (M1-M5, F1-F5)
   - Fixed supertonic_core_v1 size to 363MB
   - Added extractType: "tar.gz"

10. ✅ Created build_supertonic_release.py script
    - Downloads all files from HuggingFace
    - Creates proper archive structure
    - Ready for GitHub release upload

11. ✅ Fixed adapter path structure
    - Updated ensureCoreReady() to match extraction paths
    - Updated checkVoiceReady() path consistency

### Phase 3: Integration & Testing (4 days) - IN PROGRESS

**Blocking issue: Archive needs updating**

The current `supertonic_core.tar.gz` in GitHub releases is missing:
- `onnx/unicode_indexer.json` (required for tokenization)
- `onnx/tts.json` (model config)
- `voice_styles/*.json` files (speaker embeddings)

**To fix, run:**
```bash
python scripts/build_supertonic_release.py
gh release upload ai-cores-int8-v1 supertonic_core.tar.gz --clobber
```

**Remaining steps:**
1. **Regenerate and upload archive** with complete files
2. **Test on device** - download core, initialize, synthesize
3. **Verify tensor names** - check ONNX model input/output names match hardcoded values
4. **Add integration tests**

### Phase 4: Optimization (optional, 3 days)

10. **Thread pool tuning**
11. **Memory optimization**
12. **Streaming synthesis**

## File Structure

```
packages/platform_android_tts/android/
├── src/main/kotlin/.../onnx/
│   ├── SupertonicInference.kt    # Kotlin wrapper (update)
│   └── SupertonicNative.kt       # JNI declarations (new)
├── src/main/jni/
│   ├── supertonic_native.cpp     # JNI implementation (new)
│   └── CMakeLists.txt            # Build config (new)
└── build.gradle.kts              # Add CMake configuration
```

## Model Download

The current manifest already has Supertonic configured:

```json
{
  "id": "supertonic_core_v1",
  "engineType": "supertonic",
  "displayName": "Supertonic TTS Core",
  "url": "https://github.com/williamomeara/audiobook_flutter_assets/releases/download/ai-cores-int8-v1/supertonic_core.tar.gz",
  "sizeBytes": 363965216,
  "required": true
}
```

**Expected archive contents**:
```
supertonic_core/
├── onnx/
│   ├── text_encoder.onnx
│   ├── duration_predictor.onnx
│   ├── vector_estimator.onnx
│   ├── vocoder.onnx
│   ├── tts.json
│   └── unicode_indexer.json
└── voice_styles/
    ├── af_default/
    ├── am_default/
    └── ...
```

## Risk Mitigation

### Risk 1: ONNX Runtime API Changes
**Mitigation**: Pin to sherpa-onnx version, abstract ONNX calls

### Risk 2: Native Library Loading Issues
**Mitigation**: Test on multiple devices, use dlopen fallbacks

### Risk 3: Performance Regression
**Mitigation**: Benchmark against Piper/Kokoro, optimize hot paths

## Success Criteria

- [ ] Supertonic synthesis produces audible speech
- [ ] RTF < 1.0 (real-time capable)
- [ ] Piper and Kokoro continue working
- [ ] All integration tests pass
- [ ] Memory usage < 500MB peak

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1 | 3 days | None |
| Phase 2 | 5 days | Phase 1 |
| Phase 3 | 4 days | Phase 2 |
| Phase 4 | 3 days | Phase 3 (optional) |
| **Total** | **12-15 days** | |

## Alternative: Quick Stub Removal

If JNI is too complex, we can disable Supertonic until sherpa-onnx adds support:

1. Hide Supertonic voices from UI
2. Return clear error message if selected
3. Focus on Piper/Kokoro quality

This keeps the architecture clean for future implementation.

## Next Steps

1. **Immediate**: Create this plan document ✅
2. **Decision**: Choose Option 1 (JNI) or disable Supertonic temporarily
3. **If proceeding**: Start Phase 1 research on sherpa-onnx internals
