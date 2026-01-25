# Kokoro TTS Optimization Plan

## Overview

This document outlines a plan to upgrade Kokoro TTS implementation to use platform-optimized models for better performance on iOS (CoreML/MLX) and Android (ONNX int8 quantized).

## Status

### Completed
- ✅ **Phase 1**: Android int8 optimization (commit: 7011330)
  - Added `kokoro_core_android_v1` with int8 model (~126MB vs ~335MB)
  - Added `kokoro_core_ios_v1` for iOS (still using sherpa-onnx)
  - Updated ManifestService for platform-specific core resolution
- ✅ **Fix**: Resolved platform-specific core IDs in voice state (commit: 341b971)

### In Progress
- 🔄 **Phase 2**: iOS MLX/CoreML Integration (detailed below)

---

## Phase 2: iOS MLX Implementation - Detailed Step-by-Step

### Prerequisites
- iOS 18.0+ (MLX requirement)
- Xcode 16.0+
- CocoaPods or Swift Package Manager

### Architecture Decision
**Chosen: MLX Swift via kokoro-ios library**
- 3.3x faster than realtime on iPhone 13 Pro
- Uses Apple Neural Engine (ANE) for hardware acceleration
- Clean Swift API matching our existing interface
- Active development by mlalma

---

### Step 2.1: Add MLX Dependencies to Platform iOS TTS
**Files:** `packages/platform_ios_tts/ios/platform_ios_tts.podspec`

The challenge: Our plugin uses CocoaPods (Flutter requirement), but kokoro-ios uses SPM.

**Options:**
1. **Use SPM wrapper in CocoaPod** - Create a local Swift Package that wraps kokoro-ios
2. **Vendored framework** - Build kokoro-ios as XCFramework and vendor it
3. **Source integration** - Copy kokoro-ios source directly (may have license issues)

**Recommended: Option 1 - SPM wrapper**

```ruby
# platform_ios_tts.podspec additions:
# Add SPM dependency via Cocoapods-SPM plugin
s.dependency 'SwiftPM-KokoroSwift', :git => 'https://github.com/mlalma/kokoro-ios.git'
```

Or manually add to Podfile:
```ruby
pod 'KokoroSwift', :git => 'https://github.com/mlalma/kokoro-ios.git'
```

**Tasks:**
- [ ] 2.1.1 Fork kokoro-ios and create a podspec for it
- [ ] 2.1.2 Add kokoro-ios dependencies to platform_ios_tts.podspec
- [ ] 2.1.3 Test pod install works without breaking existing sherpa-onnx

---

### Step 2.2: Create KokoroMLXInference.swift
**Files:** `packages/platform_ios_tts/ios/Classes/inference/KokoroMLXInference.swift`

Create new inference class that mirrors KokoroSherpaInference API:

```swift
import Foundation
import KokoroSwift  // From kokoro-ios package

/// Kokoro TTS inference using MLX framework.
/// Uses Apple Neural Engine for ~3.3x faster than realtime synthesis.
class KokoroMLXInference {
    
    private var tts: KokoroTTS?
    private var currentModelPath: String?
    private var voiceEmbeddings: [String: MLXArray] = [:]  // Voice ID -> embedding
    
    var isModelLoaded: Bool {
        return tts != nil
    }
    
    /// Load the MLX Kokoro model.
    /// - Parameters:
    ///   - modelPath: Path to kokoro-v1_0.safetensors
    ///   - voiceStylesPath: Path to voice styles NPZ file
    func loadModel(modelPath: String, voiceStylesPath: String) throws {
        let modelURL = URL(fileURLWithPath: modelPath)
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TtsError.modelNotLoaded
        }
        
        // Initialize KokoroTTS with MisakiSwift G2P
        tts = KokoroTTS(modelPath: modelURL, g2p: .misaki)
        
        // Load voice style embeddings
        try loadVoiceStyles(from: voiceStylesPath)
        
        currentModelPath = modelPath
        print("[KokoroMLXInference] MLX model loaded: \(modelPath)")
    }
    
    /// Load voice style embeddings from NPZ file.
    private func loadVoiceStyles(from path: String) throws {
        // Voice styles are stored as NPZ with shape (511, 1, 256) per voice
        // See KokoroTestApp StyleLoader for reference
        guard FileManager.default.fileExists(atPath: path) else {
            throw TtsError.invalidInput("Voice styles file not found: \(path)")
        }
        
        // Load NPZ file using MLXUtilsLibrary
        // Each voice has a 256-dim style vector
        // TODO: Implement voice style loading based on KokoroTestApp
    }
    
    /// Synthesize text to audio samples.
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceName: Voice name (e.g., "af_bella")
    ///   - speed: Speech speed multiplier
    /// - Returns: Tuple of (samples, sampleRate)
    func synthesize(text: String, voiceName: String, speed: Float = 1.0) throws -> (samples: [Float], sampleRate: Int) {
        guard let tts = tts else {
            throw TtsError.modelNotLoaded
        }
        
        guard let voiceEmbedding = voiceEmbeddings[voiceName] else {
            throw TtsError.voiceNotLoaded(voiceName)
        }
        
        // Generate audio using MLX
        let audioBuffer = try tts.generateAudio(
            voice: voiceEmbedding,
            language: .enUS,  // TODO: Detect from voice name prefix
            text: text
        )
        
        return (Array(audioBuffer), 24000)  // Kokoro outputs 24kHz
    }
    
    /// Unload model and free resources.
    func unload() {
        tts = nil
        voiceEmbeddings.removeAll()
        currentModelPath = nil
        print("[KokoroMLXInference] MLX model unloaded")
    }
}
```

**Tasks:**
- [ ] 2.2.1 Create KokoroMLXInference.swift skeleton
- [ ] 2.2.2 Implement loadModel() with safetensors loading
- [ ] 2.2.3 Implement voice style loading from NPZ
- [ ] 2.2.4 Implement synthesize() using KokoroTTS.generateAudio()
- [ ] 2.2.5 Map speaker IDs to voice names (af_bella → ID 2)
- [ ] 2.2.6 Add error handling and logging

---

### Step 2.3: Update KokoroTtsService.swift for Backend Selection
**Files:** `packages/platform_ios_tts/ios/Classes/engines/KokoroTtsService.swift`

Add logic to choose between sherpa-onnx and MLX backends:

```swift
class KokoroTtsService: TtsServiceProtocol {
    let engineType: NativeEngineType = .kokoro
    
    // Dual backend support
    private var sherpaInference: KokoroSherpaInference?
    private var mlxInference: KokoroMLXInference?
    
    // Active backend type
    private enum BackendType {
        case sherpa
        case mlx
    }
    private var activeBackend: BackendType = .sherpa
    
    /// Detect which backend to use based on iOS version and model format.
    private func detectBackend(modelPath: String) -> BackendType {
        // MLX requires iOS 18.0+
        if #available(iOS 18.0, *) {
            // Check for MLX model format (safetensors)
            let safetensorsPath = (modelPath as NSString)
                .appendingPathComponent("kokoro-v1_0.safetensors")
            if FileManager.default.fileExists(atPath: safetensorsPath) {
                return .mlx
            }
        }
        
        // Fall back to sherpa-onnx
        return .sherpa
    }
    
    func loadVoice(voiceId: String, modelPath: String, speakerId: Int?, configPath: String?) async throws {
        let backend = detectBackend(modelPath: modelPath)
        
        switch backend {
        case .mlx:
            try loadWithMLX(voiceId: voiceId, modelPath: modelPath, speakerId: speakerId)
        case .sherpa:
            try loadWithSherpa(voiceId: voiceId, modelPath: modelPath, speakerId: speakerId)
        }
        
        activeBackend = backend
    }
    
    private func loadWithMLX(voiceId: String, modelPath: String, speakerId: Int?) throws {
        if mlxInference == nil {
            mlxInference = KokoroMLXInference()
        }
        
        let safetensorsPath = (modelPath as NSString)
            .appendingPathComponent("kokoro-v1_0.safetensors")
        let voiceStylesPath = (modelPath as NSString)
            .appendingPathComponent("voice_styles.npz")
        
        try mlxInference?.loadModel(
            modelPath: safetensorsPath,
            voiceStylesPath: voiceStylesPath
        )
    }
    
    private func loadWithSherpa(voiceId: String, modelPath: String, speakerId: Int?) throws {
        // Existing sherpa-onnx loading code...
    }
}
```

**Tasks:**
- [ ] 2.3.1 Add BackendType enum and detection logic
- [ ] 2.3.2 Refactor loadVoice() to support both backends
- [ ] 2.3.3 Refactor synthesize() to route to active backend
- [ ] 2.3.4 Add graceful fallback if MLX fails
- [ ] 2.3.5 Test on iOS 17 (sherpa) and iOS 18 (MLX)

---

### Step 2.4: Package MLX Model Files
**Files:** `packages/downloads/lib/manifests/voices_manifest.json`

Need to package MLX model in downloadable format:

**Model Files Required:**
1. `kokoro-v1_0.safetensors` (~600MB uncompressed) - Main model weights
2. `voice_styles.npz` (~30MB) - Voice embeddings for all 53 speakers

**Package Structure:**
```
kokoro-mlx-v1_0.tar.gz
├── kokoro-v1_0.safetensors
├── voice_styles.npz
└── .manifest  # Our marker file
```

**Tasks:**
- [ ] 2.4.1 Download kokoro-v1_0.safetensors from KokoroTestApp repo
- [ ] 2.4.2 Generate voice_styles.npz with all 53 speaker embeddings
- [ ] 2.4.3 Create tar.gz package for iOS download
- [ ] 2.4.4 Upload to williamomeara/audiobook_flutter_assets releases
- [ ] 2.4.5 Update manifest with iOS MLX core URL

**Manifest Update:**
```json
{
  "id": "kokoro_core_ios_mlx_v1",
  "engineType": "kokoro",
  "displayName": "Kokoro TTS Core (iOS MLX)",
  "url": "https://github.com/williamomeara/audiobook_flutter_assets/releases/download/kokoro-mlx-v1/kokoro-mlx-v1_0.tar.gz",
  "sizeBytes": 320000000,
  "required": true,
  "extractType": "tar.gz",
  "platform": "ios"
}
```

---

### Step 2.5: Voice Style Mapping
**Files:** Create voice_styles.npz with correct speaker ID mapping

The MLX model uses voice style vectors (256-dim) instead of integer speaker IDs.
Need to map our speaker IDs to voice names:

| Speaker ID | Voice Name | Style Index |
|------------|------------|-------------|
| 0 | af_alloy | 0 |
| 2 | af_bella | 1 |
| 6 | af_nicole | 2 |
| 9 | af_sarah | 3 |
| 10 | af_sky | 4 |
| 11 | am_adam | 5 |
| 16 | am_michael | 6 |
| 21 | bf_emma | 7 |
| 22 | bf_isabella | 8 |
| 26 | bm_george | 9 |
| 27 | bm_lewis | 10 |

**Tasks:**
- [ ] 2.5.1 Extract voice styles from KokoroTestApp Resources
- [ ] 2.5.2 Convert .npy files to combined .npz
- [ ] 2.5.3 Create speakerId-to-voiceName mapping in Swift
- [ ] 2.5.4 Update KokoroMLXInference to use mapping

---

### Step 2.6: Update ManifestService for iOS MLX Core
**Files:** `packages/downloads/lib/src/manifest_service.dart`

Update platform resolution to handle iOS MLX core:

```dart
CoreRequirement? _resolvePlatformCore(String coreId) {
  // ... existing code ...
  
  // For kokoro, resolve to platform-specific cores
  if (coreId == 'kokoro_core_v1') {
    if (_currentPlatform == 'android') {
      return _coresById['kokoro_core_android_v1'];
    } else if (_currentPlatform == 'ios') {
      // Try MLX first, fall back to sherpa
      return _coresById['kokoro_core_ios_mlx_v1'] 
          ?? _coresById['kokoro_core_ios_v1'];
    }
  }
  
  return null;
}
```

**Tasks:**
- [ ] 2.6.1 Add kokoro_core_ios_mlx_v1 to manifest
- [ ] 2.6.2 Update _resolvePlatformCore() to prefer MLX on iOS
- [ ] 2.6.3 Keep kokoro_core_ios_v1 (sherpa) as fallback
- [ ] 2.6.4 Test platform resolution on iOS

---

### Step 2.7: Integration Testing
**Tasks:**
- [ ] 2.7.1 Test on iOS Simulator (should use sherpa-onnx fallback)
- [ ] 2.7.2 Test on physical iOS device with iOS 18+ (should use MLX)
- [ ] 2.7.3 Test on physical iOS device with iOS 17 (should use sherpa)
- [ ] 2.7.4 Benchmark performance: RTF, memory, battery
- [ ] 2.7.5 Verify all 11 English voices work correctly
- [ ] 2.7.6 Test voice switching (does model reload?)

---

### Estimated Timeline

| Step | Description | Days |
|------|-------------|------|
| 2.1 | Add MLX dependencies | 0.5 |
| 2.2 | Create KokoroMLXInference | 1-2 |
| 2.3 | Update KokoroTtsService | 0.5 |
| 2.4 | Package MLX model | 1 |
| 2.5 | Voice style mapping | 0.5 |
| 2.6 | ManifestService updates | 0.5 |
| 2.7 | Integration testing | 1 |
| **Total** | | **5-6 days** |

---

### Risk Mitigation

1. **MLX compatibility issues**
   - Keep sherpa-onnx as fallback
   - Feature flag to disable MLX

2. **Model size (600MB)**
   - Use LFS for git storage
   - Download only on-demand
   - Consider delta updates

3. **Voice style format differences**
   - Test each voice individually
   - Verify output quality matches sherpa-onnx

4. **iOS version fragmentation**
   - Runtime detection for iOS 18+
   - Graceful degradation to sherpa

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
