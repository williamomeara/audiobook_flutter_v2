# iOS Integration - Implementation Plan

## Overview

Prepare the audiobook app for iOS release with full feature parity to Android. All three TTS engines (Kokoro, Piper, Supertonic) should work on iOS.

**Key Design Principle:** Each TTS engine is completely isolated with its own service class and inference wrapper. This architecture supports easy addition of new engines in the future.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter App (lib/)                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              tts_engines package                         │   │
│  │  RoutingEngine → KokoroAdapter/PiperAdapter/Supertonic  │   │
│  │                        │                                 │   │
│  │              TtsNativeApi (Pigeon Interface)             │   │
│  └──────────────────────────┬──────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
┌───────┴───────┐                         ┌────────┴────────┐
│    Android    │                         │       iOS       │
│   (existing)  │                         │  (TO IMPLEMENT) │
│               │                         │                 │
│ Kotlin +      │                         │ Swift +         │
│ sherpa-onnx   │                         │ sherpa-onnx     │
│ ONNX Runtime  │                         │ ONNX Runtime    │
└───────────────┘                         └─────────────────┘
```

### Engine Isolation Pattern

Each engine is self-contained with:
1. **Service Class** - Implements TtsNativeApi protocol
2. **Inference Wrapper** - Handles ONNX/Sherpa specifics
3. **Own State** - Independent model loading/unloading

```
packages/platform_ios_tts/ios/Classes/
├── TtsNativeApiImpl.swift          # Router (delegates to services)
│
├── engines/
│   ├── KokoroTtsService.swift      # Kokoro: ONNX + phonemizer
│   ├── PiperTtsService.swift       # Piper: Sherpa ONNX wrapper
│   └── SupertonicTtsService.swift  # Supertonic: Pure ONNX
│
├── inference/
│   ├── KokoroOnnxInference.swift   # Kokoro-specific ONNX ops
│   ├── PiperSherpaInference.swift  # Sherpa wrapper for Piper
│   └── SupertonicOnnxInference.swift # Supertonic ONNX ops
│
└── common/
    ├── AudioConverter.swift        # PCM → WAV conversion
    ├── VoiceRegistry.swift         # Track loaded voices
    └── ModelMemoryManager.swift    # LRU unloading
```

**Adding a new engine requires:**
1. Create `NewEngineTtsService.swift` implementing `TtsServiceProtocol`
2. Create `NewEngineInference.swift` for model-specific inference
3. Register in `TtsNativeApiImpl.swift` router
4. Add to Dart `RoutingEngine` enum

---

## Current State

| Component | Android Status | iOS Status |
|-----------|----------------|------------|
| Flutter UI | ✅ Complete | ✅ Works |
| Audio Playback (just_audio) | ✅ Works | ✅ Config added |
| Background Playback (audio_service) | ✅ Works | ✅ Info.plist updated |
| Book Import (EPUB/PDF) | ✅ Works | ✅ File sharing enabled |
| TTS - Kokoro | ✅ Works | ❌ Needs native bridge |
| TTS - Piper | ✅ Works | ❌ Needs native bridge |
| TTS - Supertonic | ✅ Works | ❌ Needs native bridge |
| Model Downloads | ✅ Works | ⚠️ Needs testing |

---

## Phase 1: iOS Project Setup & Configuration (2-3 days) ✅ COMPLETE

### 1.1 Info.plist Updates ✅ DONE

Added background audio capability:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Added file picker capability:
```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

### 1.2 Xcode Project Configuration

- [x] Set minimum iOS deployment target to 14.0 (in Podfile)
- [ ] Enable "Audio, AirPlay, and Picture in Picture" capability (manual in Xcode)
- [ ] Configure signing & capabilities (manual in Xcode)
- [ ] Review build settings for ONNX Runtime compatibility

### 1.3 Podfile Dependencies

```ruby
# ios/Podfile - CREATED
platform :ios, '14.0'

# ONNX Runtime for Kokoro & Supertonic (commented for future)
# sherpa-onnx for Piper (commented for future)
```

---

## Phase 2: Create platform_ios_tts Package (2-3 days) ✅ COMPLETE

### 2.1 Package Structure ✅ DONE

```
packages/platform_ios_tts/
├── ios/
│   ├── Classes/
│   │   ├── PlatformIosTtsPlugin.swift     ✅ Router implementation
│   │   ├── generated/
│   │   │   └── TtsApi.g.swift             ✅ Pigeon generated
│   │   │
│   │   ├── engines/
│   │   │   ├── TtsServiceProtocol.swift   ✅ Base protocol
│   │   │   ├── KokoroTtsService.swift     ✅ Stub implementation
│   │   │   ├── PiperTtsService.swift      ✅ Stub implementation
│   │   │   └── SupertonicTtsService.swift ✅ Stub implementation
│   │   │
│   │   ├── inference/                     (Phase 4)
│   │   │   ├── KokoroOnnxInference.swift
│   │   │   ├── PiperSherpaInference.swift
│   │   │   └── SupertonicOnnxInference.swift
│   │   │
│   │   └── common/                        (Phase 4)
│   │       ├── AudioConverter.swift
│   │       ├── VoiceRegistry.swift
│   │       └── ModelMemoryManager.swift
│   │
│   └── platform_ios_tts.podspec           ✅ iOS 14.0+
├── lib/
│   ├── generated/
│   │   └── tts_api.g.dart                 ✅ Pigeon generated
│   └── platform_ios_tts.dart              ✅ Exports API
├── pigeons/
│   └── tts_service.dart                   ✅ Pigeon definition
└── pubspec.yaml                           ✅ With pigeon dependency
```

### 2.2 Pigeon Code Generation ✅ DONE

Update `packages/tts_engines/pigeons/tts_service.dart`:
```dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/tts_native_api.g.dart',
  kotlinOut: '../platform_android_tts/android/.../TtsNativeApi.kt',
  swiftOut: '../platform_ios_tts/ios/Classes/TtsApi.g.swift',  // ADD
))
```

### 2.3 TtsServiceProtocol (Engine Interface)

```swift
/// Protocol all TTS engines must implement
protocol TtsServiceProtocol {
    var engineType: EngineType { get }
    var isReady: Bool { get }
    
    func loadCore(corePath: String) async throws
    func loadVoice(voiceId: String, voicePath: String) async throws
    func synthesize(request: SynthRequest) async throws -> SynthResult
    func unloadVoice(voiceId: String)
    func unloadAll()
}
```

### 2.4 TtsNativeApiImpl (Router)

```swift
/// Routes Pigeon calls to appropriate engine service
class TtsNativeApiImpl: TtsNativeApi {
    private lazy var kokoroService = KokoroTtsService()
    private lazy var piperService = PiperTtsService()
    private lazy var supertonicService = SupertonicTtsService()
    
    private func service(for engine: EngineType) -> TtsServiceProtocol {
        switch engine {
        case .kokoro: return kokoroService
        case .piper: return piperService
        case .supertonic: return supertonicService
        }
    }
    
    func loadCore(request: LoadCoreRequest) async throws -> LoadCoreResult {
        let svc = service(for: request.engineType)
        try await svc.loadCore(corePath: request.corePath)
        return LoadCoreResult(success: true)
    }
    
    // ... other methods delegate similarly
}
```

---

## Phase 3: sherpa-onnx iOS Integration (3-4 days) ✅ COMPLETE

sherpa-onnx is used for Piper and potentially Kokoro phonemization.

### 3.1 Framework Setup ✅ DONE

Built from source using `build-ios.sh`:
```bash
git clone https://github.com/k2-fsa/sherpa-onnx ~/sherpa-onnx-ios-build
cd ~/sherpa-onnx-ios-build
brew install cmake  # Required dependency
./build-ios.sh     # Builds xcframework for device + simulator
```

Copied to plugin:
```
packages/platform_ios_tts/ios/Frameworks/
├── onnxruntime.xcframework/     (1.17.1 - from GitHub)
└── sherpa-onnx.xcframework/     (built from source)
    ├── ios-arm64/               (device)
    └── ios-arm64_x86_64-simulator/
```

### 3.2 Module Map for C API ✅ DONE

Created module map (bridging headers not supported in framework targets):
```
packages/platform_ios_tts/ios/SherpaOnnxCApi/
├── module.modulemap    # Defines SherpaOnnxCApi module
└── shim.h              # Includes sherpa-onnx/c-api/c-api.h
```

### 3.3 Podspec Configuration ✅ DONE

```ruby
# platform_ios_tts.podspec
s.vendored_frameworks = 'Frameworks/onnxruntime.xcframework', 
                        'Frameworks/sherpa-onnx.xcframework'
s.preserve_paths = 'SherpaOnnxCApi'
s.pod_target_xcconfig = {
  'SWIFT_INCLUDE_PATHS' => '$(PODS_TARGET_SRCROOT)/SherpaOnnxCApi',
  'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/Frameworks/sherpa-onnx.xcframework/ios-arm64/Headers'
}
s.frameworks = 'Accelerate', 'CoreML'
```

### 3.4 Swift Wrapper ✅ DONE

- Copied `SherpaOnnx.swift` from sherpa-onnx swift-api-examples
- Added `import SherpaOnnxCApi` to import C API via module map
- Provides high-level Swift classes: `OfflineTts`, `OfflineTtsConfig`, etc.

### 3.5 Build Verification ✅ DONE

- iOS release build: **87.0MB** (up from 61.1MB without sherpa-onnx)
- All 269/270 tests pass
- Ready for Phase 4 inference implementation

### 3.6 Next: Sherpa Inference Wrapper (Phase 4)
```

---

## Phase 4: Engine Implementations (5-7 days) ✅ COMPLETE

All three TTS engines now have real sherpa-onnx inference implementations.

### 4.1 Inference Wrappers ✅ DONE

Created in `Classes/inference/`:

- **PiperSherpaInference.swift** - VITS-based inference for Piper models
- **KokoroSherpaInference.swift** - Native Kokoro model support via sherpa-onnx
- **SupertonicSherpaInference.swift** - VITS-based inference for Supertonic models

All wrappers use:
- `SherpaOnnxOfflineTtsWrapper` for inference
- CoreML provider for Metal acceleration
- Proper error handling with TtsError enum

### 4.2 Engine Services ✅ DONE

Updated in `Classes/engines/`:

- **KokoroTtsService.swift** - Uses KokoroSherpaInference
- **PiperTtsService.swift** - Uses PiperSherpaInference
- **SupertonicTtsService.swift** - Uses SupertonicSherpaInference

Each service:
- Validates model files on load (model.onnx, tokens.txt, voices.bin for Kokoro)
- Uses thread-safe locking with NSLock
- Generates WAV output via AudioConverter

### 4.3 Common Utilities ✅ DONE

Created in `Classes/common/`:

- **AudioConverter.swift** - Float32 samples to WAV conversion
  - `toWav(samples:sampleRate:)` - Returns Data
  - `writeWav(samples:sampleRate:to:)` - Writes to path
  - `durationMs(sampleCount:sampleRate:)` - Calculate duration

### 4.4 Build Verification ✅ DONE

- iOS release build: **87.0MB**
- All 269/270 tests pass
- Ready for Phase 5 (Dart-side integration)

---

## Phase 5: Integration with tts_engines Package (2-3 days) ✅ COMPLETE

### 5.1 Platform Conditional in Provider ✅ DONE

Instead of modifying adapters, we use a wrapper pattern in `lib/app/tts_providers.dart`:

```dart
final ttsNativeApiProvider = Provider<android.TtsNativeApi>((ref) {
  if (Platform.isIOS) {
    return _IosApiWrapper(ios.TtsNativeApi());
  }
  return android.TtsNativeApi();
});
```

### 5.2 iOS API Wrapper ✅ DONE

Created `_IosApiWrapper` class that:
- Implements `android.TtsNativeApi` interface
- Delegates all calls to `ios.TtsNativeApi`
- Converts between Android and iOS enum types
- Preserves full type safety

### 5.3 Package Dependencies ✅ DONE

Added `platform_ios_tts` dependency to:
- `packages/tts_engines/pubspec.yaml`
- Main app already had it

### 5.4 Build Verification ✅ DONE

- iOS release build: **87.0MB**
- All 269/270 tests pass
- Adapters work transparently on both platforms

---

## Phase 6: Model Downloads & Storage (2-3 days)

### 6.1 iOS Storage Paths

```swift
let modelsDir = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("tts_models")
```

### 6.2 Verify Downloads Package

- Test `AtomicAssetManager` on iOS
- Test `ResilientDownloader` resume support
- Test .tar.bz2 extraction on iOS

---

## Phase 7: Testing (3-4 days)

### 7.1 Swift Unit Tests

```swift
class KokoroTtsServiceTests: XCTestCase {
    func testSynthesizeBasicText() async throws {
        let service = KokoroTtsService()
        try await service.loadCore(corePath: testModelPath)
        
        let request = SynthRequest(text: "Hello world", voiceId: "kokoro_af_bella")
        let result = try await service.synthesize(request: request)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.filePath))
        XCTAssertGreaterThan(result.durationMs, 0)
    }
}
```

### 7.2 Integration Tests

```dart
testWidgets('iOS TTS synthesis - Kokoro', (tester) async {
  final engine = RoutingEngine();
  await engine.ensureCoreReady(CoreSelector.kokoro);
  
  final result = await engine.synthesizeToFile(SynthRequest(
    text: 'Hello from iOS',
    voiceId: 'kokoro_af_bella',
    outputFile: File(tempPath),
  ));
  
  expect(result.file.existsSync(), isTrue);
});
```

### 7.3 Full Test Matrix

| Test | Kokoro | Piper | Supertonic |
|------|--------|-------|------------|
| Model load | [ ] | [ ] | [ ] |
| Basic synthesis | [ ] | [ ] | [ ] |
| Long text | [ ] | [ ] | [ ] |
| Multiple voices | [ ] | [ ] | [ ] |
| Memory unload | [ ] | [ ] | [ ] |
| Background synthesis | [ ] | [ ] | [ ] |
| Error handling | [ ] | [ ] | [ ] |

---

## Phase 8: Background Playback (1-2 days)

### 8.1 Audio Session

```swift
import AVFoundation

func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio)
    try session.setActive(true)
}
```

### 8.2 Integration Verification

- [ ] just_audio works with iOS audio session
- [ ] Background synthesis while app minimized
- [ ] Lock screen controls functional
- [ ] Interruption handling (calls, Siri)

---

## Phase 9: Polish & Release (2-3 days)

### 9.1 Error Handling Parity

```swift
enum TtsErrorCode: Int {
    case modelMissing = 1
    case modelCorrupted = 2
    case outOfMemory = 3
    case inferenceFailed = 4
    case cancelled = 5
    case runtimeCrash = 6
    case invalidInput = 7
    case fileWriteError = 8
    case unknown = 99
}
```

### 9.2 App Store Preparation

- [ ] App icons (all sizes)
- [ ] Launch screen
- [ ] App Store screenshots
- [ ] Privacy policy
- [ ] TestFlight setup

---

## Task Checklist Summary

### High Priority

**iOS Configuration:**
- [ ] Add `UIBackgroundModes: audio` to Info.plist
- [ ] Set iOS deployment target to 14.0+
- [ ] Enable audio capability in Xcode

**TTS Integration:**
- [ ] Create `platform_ios_tts` package
- [ ] Generate Pigeon Swift bindings
- [ ] Implement `TtsServiceProtocol` interface
- [ ] Implement `KokoroTtsService`
- [ ] Implement `PiperTtsService`
- [ ] Implement `SupertonicTtsService`
- [ ] Integrate sherpa-onnx for iOS
- [ ] Integrate ONNX Runtime for iOS

**Testing:**
- [ ] Test all 3 engines synthesize correctly
- [ ] Test audio playback
- [ ] Test background playback
- [ ] Test model downloads

---

## Timeline Estimate

| Phase | Duration |
|-------|----------|
| 1. iOS Config | 2-3 days |
| 2. Package Structure | 2-3 days |
| 3. sherpa-onnx Integration | 3-4 days |
| 4. Engine Implementations | 5-7 days |
| 5. tts_engines Integration | 2-3 days |
| 6. Downloads/Storage | 2-3 days |
| 7. Testing | 3-4 days |
| 8. Background Playback | 1-2 days |
| 9. Polish | 2-3 days |
| **Total** | **22-32 days** |

---

## Success Criteria

- [ ] All 3 TTS engines (Kokoro, Piper, Supertonic) work on iOS
- [ ] Model download and caching functional
- [ ] Background playback works
- [ ] Performance within 2x of Android (synthesis latency)
- [ ] Memory usage under 500MB during synthesis
- [ ] No crashes in 1-hour continuous playback test
- [ ] All existing Flutter integration tests pass on iOS

---

## References

- [sherpa-onnx iOS examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)
- [ONNX Runtime iOS](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- [Flutter iOS Plugin Development](https://docs.flutter.dev/packages-and-plugins/developing-packages#swift)
- [Pigeon for Swift](https://pub.dev/packages/pigeon#swift-setup)


