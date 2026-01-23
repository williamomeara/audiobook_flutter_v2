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

## Phase 2: Create platform_ios_tts Package (2-3 days)

### 2.1 Package Structure

```
packages/platform_ios_tts/
├── ios/
│   ├── Classes/
│   │   ├── PlatformIosTtsPlugin.swift
│   │   ├── TtsApi.g.swift (Pigeon generated)
│   │   │
│   │   ├── engines/
│   │   │   ├── TtsServiceProtocol.swift
│   │   │   ├── KokoroTtsService.swift
│   │   │   ├── PiperTtsService.swift
│   │   │   └── SupertonicTtsService.swift
│   │   │
│   │   ├── inference/
│   │   │   ├── KokoroOnnxInference.swift
│   │   │   ├── PiperSherpaInference.swift
│   │   │   └── SupertonicOnnxInference.swift
│   │   │
│   │   └── common/
│   │       ├── AudioConverter.swift
│   │       ├── VoiceRegistry.swift
│   │       └── ModelMemoryManager.swift
│   │
│   └── platform_ios_tts.podspec
├── lib/
│   └── platform_ios_tts.dart
└── pubspec.yaml
```

### 2.2 Pigeon Code Generation

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

## Phase 3: sherpa-onnx iOS Integration (3-4 days)

sherpa-onnx is used for Piper and potentially Kokoro phonemization.

### 3.1 Framework Options

1. **Pre-built XCFramework** (recommended)
   - Download from sherpa-onnx releases
   - Add to `ios/Frameworks/`

2. **Build from source**
   ```bash
   git clone https://github.com/k2-fsa/sherpa-onnx
   ./build-ios.sh
   ```

### 3.2 Sherpa Wrapper

```swift
// PiperSherpaInference.swift
import SherpaOnnxTts

class PiperSherpaInference {
    private var tts: OfflineTts?
    
    func loadModel(modelPath: String, tokensPath: String) throws {
        let config = OfflineTtsConfig()
        config.model.vitsModel = modelPath
        config.model.tokens = tokensPath
        config.model.numThreads = 2
        config.model.provider = "coreml"  // Metal acceleration
        
        tts = OfflineTts(config: config)
    }
    
    func synthesize(text: String, speakerId: Int, speed: Float) throws -> [Float] {
        guard let tts = tts else { throw TtsError.modelNotLoaded }
        let audio = tts.generate(text: text, sid: Int32(speakerId), speed: speed)
        return audio.samples
    }
    
    func unload() {
        tts = nil
    }
}
```

---

## Phase 4: Engine Implementations (5-7 days)

### 4.1 KokoroTtsService

```swift
class KokoroTtsService: TtsServiceProtocol {
    let engineType: EngineType = .kokoro
    
    private let inference = KokoroOnnxInference()
    private var loadedVoices: [String: VoiceInfo] = [:]
    private let memoryManager: ModelMemoryManager
    
    var isReady: Bool { inference.isModelLoaded }
    
    func loadCore(corePath: String) async throws {
        try await inference.loadModel(path: corePath)
    }
    
    func loadVoice(voiceId: String, voicePath: String) async throws {
        memoryManager.ensureCapacity(for: .kokoro)
        // Load voice-specific config
        loadedVoices[voiceId] = VoiceInfo(...)
    }
    
    func synthesize(request: SynthRequest) async throws -> SynthResult {
        let samples = try await inference.generate(
            text: request.text,
            voiceId: request.voiceId,
            speed: request.speed
        )
        
        let wavData = AudioConverter.toWav(samples: samples, sampleRate: 24000)
        try wavData.write(to: URL(fileURLWithPath: request.outputPath))
        
        return SynthResult(
            filePath: request.outputPath,
            durationMs: Int64(samples.count * 1000 / 24000),
            sampleRate: 24000
        )
    }
    
    func unloadVoice(voiceId: String) {
        loadedVoices.removeValue(forKey: voiceId)
    }
    
    func unloadAll() {
        loadedVoices.removeAll()
        inference.unload()
    }
}
```

### 4.2 PiperTtsService

```swift
class PiperTtsService: TtsServiceProtocol {
    let engineType: EngineType = .piper
    
    private let inference = PiperSherpaInference()
    // ... similar pattern to Kokoro
}
```

### 4.3 SupertonicTtsService

```swift
class SupertonicTtsService: TtsServiceProtocol {
    let engineType: EngineType = .supertonic
    
    private let inference = SupertonicOnnxInference()
    // ... similar pattern, uses raw ONNX Runtime
}
```

### 4.4 Common Utilities

```swift
// AudioConverter.swift
class AudioConverter {
    static func toWav(samples: [Float], sampleRate: Int) -> Data {
        var buffer = Data()
        // WAV header (44 bytes)
        buffer.append(wavHeader(dataSize: samples.count * 2, sampleRate: sampleRate))
        // Audio data (Float32 → Int16)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767)
            withUnsafeBytes(of: int16.littleEndian) { buffer.append(contentsOf: $0) }
        }
        return buffer
    }
}

// VoiceRegistry.swift
class VoiceRegistry {
    struct VoiceInfo {
        let voiceId: String
        let engine: EngineType
        let modelPath: String
        let lastUsed: Date
    }
    
    func getVoice(id: String) -> VoiceInfo?
    func registerVoice(_ info: VoiceInfo)
    func getLeastRecentlyUsed() -> VoiceInfo?
}

// ModelMemoryManager.swift
class ModelMemoryManager {
    private let maxLoadedModels = 2  // iOS memory constraints
    
    func ensureCapacity(for engine: EngineType) {
        if loadedModels.count >= maxLoadedModels {
            unloadLeastRecentlyUsed()
        }
    }
}
```

---

## Phase 5: Integration with tts_engines Package (2-3 days)

### 5.1 Platform Conditional in Adapters

```dart
// packages/tts_engines/lib/src/adapters/kokoro_adapter.dart
class KokoroAdapter implements AiVoiceEngine {
  late final TtsNativeApi _nativeApi;
  
  KokoroAdapter() {
    if (Platform.isAndroid) {
      _nativeApi = AndroidTtsNativeApi();  // Existing
    } else if (Platform.isIOS) {
      _nativeApi = IosTtsNativeApi();      // NEW
    }
  }
}
```

### 5.2 Plugin Registration

```dart
// packages/platform_ios_tts/lib/platform_ios_tts.dart
class IosTtsNativeApi implements TtsNativeApi {
  // Pigeon-generated implementation
}
```

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


