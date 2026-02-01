# iOS Voice Swap Freeze Analysis

## Problem Summary (RESOLVED ✅)

When switching from Kokoro to Supertonic voice on iOS, the UI used to freeze for approximately **50 seconds**. This was caused by CoreML model compilation at runtime.

**Status: FIXED** - We switched from CoreML to ONNX Runtime, matching the official Supertonic implementation.

## Original Root Cause (Historical)

The freeze occurred because CoreML model compilation took ~50 seconds on first use of Supertonic voice on iOS. CoreML models required device-specific compilation from `.mlpackage` to `.mlmodelc` format, which blocked the main thread despite background threading attempts.

## Solution Implemented: ONNX Runtime

We replaced the CoreML implementation with **ONNX Runtime**, matching the official `supertone-inc/supertonic` repository approach.

### Why ONNX Runtime?

| Aspect | ONNX Runtime |
|--------|--------------|
| **First load time** | 1-3 seconds |
| **Subsequent loads** | 1-3 seconds |
| **Cross-platform** | iOS + Android (same code) |
| **User experience** | Consistent, no compilation freeze |
| **Official support** | ✅ Matches Supertonic SDK |

### Implementation Details

1. **Created ONNX Runtime Swift Bindings**
   - `OnnxRuntimeCApi` module map (similar to SherpaOnnxCApi)
   - `ort_shim.h` header for ONNX Runtime C API
   - `OrtWrapper.swift` Swift wrapper

2. **Ported 4-Stage Inference Pipeline**
   - `SupertonicOnnxInference.swift` implements the full pipeline:
     - Duration predictor → text encoder → vector estimator (20 denoising steps) → vocoder
   - Uses same ONNX models as Android

3. **Updated Download System**
   - Models now download from Hugging Face (reliable public source)
   - Multi-file download: 4 ONNX models + configs + voice styles
   - Total ~267MB

### Files Changed

- `packages/platform_ios_tts/ios/Classes/inference/SupertonicOnnxInference.swift` - New ONNX-based inference
- `packages/platform_ios_tts/ios/Classes/engines/SupertonicTtsService.swift` - Updated to use ONNX
- `packages/platform_ios_tts/ios/Classes/onnx/OrtWrapper.swift` - ONNX Runtime Swift wrapper
- `packages/downloads/lib/manifests/voices_manifest.json` - Updated to Hugging Face multi-file download
- Removed: `SupertonicCoreMLInference.swift`, `ios/Assets/supertonic_coreml/` (~77MB deleted)

## Additional Fix: Main Thread Blocking

During investigation, we discovered another issue causing UI jankiness:

**Problem:** `getCoreStatus` and `isVoiceReady` in `PlatformIosTtsPlugin.swift` ran on the main thread, calling `svc.isReady` which acquired a lock held by synthesis for 6+ seconds.

**Fix:** Wrapped both methods in `Task.detached` to prevent main thread blocking.

## Current Performance

- **Engine initialization:** ~2 seconds
- **Voice loading:** <100ms
- **No UI freezes during synthesis**
- **Background thread properly handles all TTS operations**

## References

- [Official Supertonic Repository](https://github.com/supertone-inc/supertonic) - Uses ONNX Runtime
- [ONNX Runtime iOS](https://onnxruntime.ai/docs/)
- [Hugging Face Supertonic Models](https://huggingface.co/Supertone/supertonic)
