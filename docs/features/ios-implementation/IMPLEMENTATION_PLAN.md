# iOS TTS Implementation Plan

## Overview

This document outlines the plan to implement full iOS support for the audiobook app's AI-powered text-to-speech system. The implementation will mirror the existing Android architecture while leveraging iOS-native APIs and optimizations.

## Current State

- ✅ Android implementation complete (Kokoro, Piper, Supertonic engines)
- ✅ Platform-agnostic Dart abstraction layer (`tts_engines` package)
- ❌ No iOS native TTS implementation
- ❌ iOS app shell exists but lacks TTS functionality

## Architecture Goal

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter App (lib/)                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              tts_engines package                         │   │
│  │  RoutingEngine → KokoroAdapter/PiperAdapter/Supertonic  │   │
│  │                        │                                 │   │
│  │              TtsNativeApi (Pigeon)                       │   │
│  └──────────────────────────┬──────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
┌───────┴───────┐                         ┌────────┴────────┐
│    Android    │                         │       iOS       │
│ (existing)    │                         │  (TO IMPLEMENT) │
│               │                         │                 │
│ Kotlin +      │                         │ Swift +         │
│ sherpa-onnx   │                         │ sherpa-onnx     │
│ ONNX Runtime  │                         │ ONNX Runtime    │
└───────────────┘                         └─────────────────┘
```

## Phase 1: Foundation & Project Setup (2-3 days)

### 1.1 Create platform_ios_tts Package

```
packages/
└── platform_ios_tts/
    ├── ios/
    │   ├── Classes/
    │   │   ├── PlatformIosTtsPlugin.swift
    │   │   ├── TtsApi.g.swift (Pigeon generated)
    │   │   ├── KokoroTtsService.swift
    │   │   ├── PiperTtsService.swift
    │   │   ├── SupertonicTtsService.swift
    │   │   └── inference/
    │   │       ├── KokoroOnnxInference.swift
    │   │       ├── PiperSherpaInference.swift
    │   │       └── SupertonicOnnxInference.swift
    │   └── platform_ios_tts.podspec
    ├── lib/
    │   └── platform_ios_tts.dart
    ├── pigeons/
    │   └── tts_api.dart (shared with Android)
    └── pubspec.yaml
```

### 1.2 Configure Pigeon for iOS

Update `pigeons/tts_api.dart` to generate Swift code:

```dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/generated/tts_api.g.dart',
  swiftOut: 'ios/Classes/TtsApi.g.swift',
  kotlinOut: 'android/src/main/kotlin/TtsApi.g.kt',
))
```

### 1.3 Add CocoaPods Dependencies

```ruby
# platform_ios_tts.podspec
Pod::Spec.new do |s|
  s.name             = 'platform_ios_tts'
  s.version          = '0.0.1'
  s.summary          = 'iOS TTS platform implementation'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
  
  s.dependency 'Flutter'
  s.dependency 'onnxruntime-swift', '~> 1.19'
  # sherpa-onnx iOS pod (if available) or vendored framework
  
  s.source_files = 'Classes/**/*'
end
```

### 1.4 Tasks

- [ ] Create `platform_ios_tts` package directory structure
- [ ] Configure pubspec.yaml with Flutter plugin settings for iOS
- [ ] Create podspec with ONNX Runtime dependency
- [ ] Generate Pigeon bindings for Swift
- [ ] Create plugin entry point (`PlatformIosTtsPlugin.swift`)
- [ ] Verify plugin registration in main app's ios/Podfile

---

## Phase 2: sherpa-onnx iOS Integration (3-4 days)

### 2.1 sherpa-onnx Framework

sherpa-onnx provides iOS support via:
- Pre-built XCFramework (recommended)
- CocoaPods distribution (check availability)
- Manual build from source

**Recommended approach**: Use pre-built framework from sherpa-onnx releases.

### 2.2 Framework Integration

```swift
// SherpaOnnxWrapper.swift
import SherpaOnnxTts

class SherpaOnnxWrapper {
    private var tts: OfflineTts?
    
    func loadModel(modelPath: String, tokensPath: String) throws {
        let config = OfflineTtsConfig()
        config.model.vitsModel = modelPath
        config.model.tokens = tokensPath
        config.model.numThreads = 2
        config.model.provider = "coreml"  // or "cpu"
        
        tts = OfflineTts(config: config)
    }
    
    func synthesize(text: String, speakerId: Int, speed: Float) throws -> [Float] {
        guard let tts = tts else { throw TtsError.modelNotLoaded }
        let audio = tts.generate(text: text, sid: Int32(speakerId), speed: speed)
        return audio.samples
    }
}
```

### 2.3 Tasks

- [ ] Download sherpa-onnx iOS XCFramework
- [ ] Add to `ios/Frameworks/` or via CocoaPods
- [ ] Create `SherpaOnnxWrapper.swift` bridge class
- [ ] Test basic TTS generation with sample model
- [ ] Verify CoreML provider works (Metal acceleration)

---

## Phase 3: Core Engine Implementations (5-7 days)

### 3.1 KokoroTtsService

```swift
class KokoroTtsService: TtsNativeApi {
    private let inference: KokoroOnnxInference
    private var loadedVoices: [String: VoiceInfo] = [:]
    
    func loadCore(corePath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.inference.loadModel(path: corePath)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func synthesize(request: SynthRequest, completion: @escaping (Result<SynthResult, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let samples = try self.inference.generate(
                    text: request.text,
                    voiceId: request.voiceId,
                    speed: request.speed
                )
                
                let wavData = self.convertToWav(samples: samples, sampleRate: 24000)
                try wavData.write(to: URL(fileURLWithPath: request.outputPath))
                
                let result = SynthResult(
                    filePath: request.outputPath,
                    durationMs: Int64(samples.count * 1000 / 24000),
                    sampleRate: 24000
                )
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

### 3.2 PiperTtsService

Similar structure using sherpa-onnx's Piper/VITS model loader.

### 3.3 SupertonicTtsService

Uses raw ONNX Runtime for Supertonic models (same as Android).

### 3.4 Audio Processing Utilities

```swift
class AudioConverter {
    /// Convert Float32 samples to 16-bit PCM WAV
    static func toWav(samples: [Float], sampleRate: Int) -> Data {
        var buffer = Data()
        
        // WAV header (44 bytes)
        let dataSize = samples.count * 2  // 16-bit = 2 bytes per sample
        buffer.append(wavHeader(dataSize: dataSize, sampleRate: sampleRate))
        
        // Audio data (Float32 -> Int16)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767)
            withUnsafeBytes(of: int16.littleEndian) { buffer.append(contentsOf: $0) }
        }
        
        return buffer
    }
    
    private static func wavHeader(dataSize: Int, sampleRate: Int) -> Data {
        // Standard WAV header construction
        // ... (RIFF, fmt, data chunks)
    }
}
```

### 3.5 Tasks

- [ ] Implement `KokoroTtsService.swift` with full Pigeon API conformance
- [ ] Implement `PiperTtsService.swift`
- [ ] Implement `SupertonicTtsService.swift`
- [ ] Create `AudioConverter.swift` for PCM→WAV conversion
- [ ] Add atomic file writing (temp file + rename)
- [ ] Implement error handling matching Android error codes

---

## Phase 4: Model Management & Caching (2-3 days)

### 4.1 Model Storage

iOS model storage locations:
```swift
let modelsDir = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("tts_models")
```

### 4.2 Voice Registry

```swift
class VoiceRegistry {
    struct VoiceInfo {
        let voiceId: String
        let engine: EngineType
        let modelPath: String
        let tokensPath: String?
        let speakerId: Int?
        let lastUsed: Date
    }
    
    func getVoice(id: String) -> VoiceInfo?
    func registerVoice(_ info: VoiceInfo)
    func getLeastRecentlyUsed() -> VoiceInfo?
}
```

### 4.3 Memory Management

```swift
class ModelMemoryManager {
    private let maxLoadedModels = 2  // iOS memory constraints
    
    func ensureCapacity(for engine: EngineType) {
        if loadedModels.count >= maxLoadedModels {
            unloadLeastRecentlyUsed()
        }
    }
    
    func unloadLeastRecentlyUsed() {
        // Release ONNX session memory
    }
}
```

### 4.4 Tasks

- [ ] Implement model storage path resolution
- [ ] Create voice registry with persistence (UserDefaults or JSON)
- [ ] Implement LRU model unloading for memory management
- [ ] Add model verification (checksum validation)
- [ ] Sync with existing download manifests from `downloads` package

---

## Phase 5: Integration with tts_engines (2-3 days)

### 5.1 Update Adapter Registration

In `tts_engines` package, update adapters to use iOS native API when on iOS:

```dart
// lib/src/adapters/kokoro_adapter.dart
class KokoroAdapter implements AiVoiceEngine {
  late final TtsNativeApi _nativeApi;
  
  KokoroAdapter() {
    if (Platform.isAndroid) {
      _nativeApi = AndroidTtsNativeApi();
    } else if (Platform.isIOS) {
      _nativeApi = IosTtsNativeApi();  // NEW
    }
  }
}
```

### 5.2 Platform Channel Setup

Ensure Pigeon-generated code connects iOS implementation:

```dart
// platform_ios_tts/lib/platform_ios_tts.dart
class IosTtsNativeApi implements TtsNativeApi {
  final _channel = const MethodChannel('platform_ios_tts');
  // Or use Pigeon's generated Swift host API bindings
}
```

### 5.3 Tasks

- [ ] Update `tts_engines` to conditionally use iOS native API
- [ ] Verify Pigeon bindings work end-to-end
- [ ] Add Platform.isIOS checks where needed
- [ ] Test synthesis pipeline from Flutter → Swift → back

---

## Phase 6: Model Downloads for iOS (2-3 days)

### 6.1 Update Download Manifests

Ensure `packages/downloads/lib/manifests/voices_manifest.json` includes iOS-compatible model URLs if different.

### 6.2 iOS-Specific Model Considerations

- Same models work cross-platform (ONNX is portable)
- May need CoreML-optimized variants for best performance
- sherpa-onnx handles model format abstraction

### 6.3 Tasks

- [ ] Verify existing model downloads work on iOS (URL accessibility)
- [ ] Add any iOS-specific model variants if needed
- [ ] Test `AtomicAssetManager` and `ResilientDownloader` on iOS
- [ ] Verify extraction of .tar.bz2 archives on iOS

---

## Phase 7: Testing & Optimization (3-4 days)

### 7.1 Unit Tests

```swift
// Tests/KokoroTtsServiceTests.swift
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
// integration_test/ios_tts_test.dart
testWidgets('iOS TTS synthesis', (tester) async {
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

### 7.3 Performance Optimization

- Enable CoreML provider for ONNX Runtime (Metal GPU acceleration)
- Profile memory usage with Instruments
- Optimize audio buffer sizes for streaming (future)
- Test on various iOS devices (iPhone, iPad, older models)

### 7.4 Tasks

- [ ] Write Swift unit tests for each TTS service
- [ ] Write Flutter integration tests for iOS
- [ ] Profile synthesis latency on real devices
- [ ] Enable CoreML acceleration and benchmark
- [ ] Test memory pressure handling
- [ ] Test background audio synthesis

---

## Phase 8: Background Playback (1-2 days)

### 8.1 Audio Session Configuration

```swift
import AVFoundation

func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio)
    try session.setActive(true)
}
```

### 8.2 Integration with Existing Playback Package

The `playback` package already uses `audio_service` for background playback. iOS native code should:
- Not conflict with Flutter's audio session management
- Allow concurrent synthesis and playback

### 8.3 Tasks

- [ ] Verify audio session compatibility with just_audio
- [ ] Test background synthesis (app minimized)
- [ ] Ensure lock screen controls work
- [ ] Test interruption handling (calls, Siri)

---

## Phase 9: Final Integration & Polish (2-3 days)

### 9.1 Error Handling Parity

Ensure iOS error codes match Android for consistent UI:

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

### 9.2 Logging

```swift
import os

private let logger = Logger(subsystem: "com.example.audiobook", category: "TTS")

logger.info("Loading Kokoro model...")
logger.error("Synthesis failed: \(error.localizedDescription)")
```

### 9.3 Tasks

- [ ] Standardize error codes across platforms
- [ ] Add structured logging for debugging
- [ ] Update Settings screen for iOS-specific info
- [ ] Test complete user flow on iOS
- [ ] Update documentation

---

## Estimated Timeline

| Phase | Description | Duration |
|-------|-------------|----------|
| 1 | Foundation & Project Setup | 2-3 days |
| 2 | sherpa-onnx iOS Integration | 3-4 days |
| 3 | Core Engine Implementations | 5-7 days |
| 4 | Model Management & Caching | 2-3 days |
| 5 | Integration with tts_engines | 2-3 days |
| 6 | Model Downloads for iOS | 2-3 days |
| 7 | Testing & Optimization | 3-4 days |
| 8 | Background Playback | 1-2 days |
| 9 | Final Integration & Polish | 2-3 days |
| **Total** | | **22-32 days** |

---

## Dependencies & Prerequisites

### Required

- macOS development machine with Xcode 15+
- iOS device(s) for testing (iPhone 11+ recommended)
- Apple Developer account for device deployment
- CocoaPods installed

### External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| ONNX Runtime | 1.19+ | Neural network inference |
| sherpa-onnx | 1.10+ | TTS model wrapper |
| Flutter | 3.7+ | Cross-platform framework |

### Model Files

Same models as Android:
- Kokoro: `kokoro-v1.0-onnx.tar.bz2` (~500MB)
- Piper voices: ~30-100MB each
- Supertonic: ~200MB per voice

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| sherpa-onnx iOS build issues | Medium | High | Use pre-built framework, fallback to raw ONNX |
| Memory constraints on older iPhones | Medium | Medium | Aggressive LRU unloading, model streaming |
| CoreML compatibility | Low | Medium | Fallback to CPU provider |
| App Store ONNX size limits | Low | Low | On-demand model downloads |

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

## Files to Create/Modify

### New Files

```
packages/platform_ios_tts/
├── ios/
│   ├── Classes/
│   │   ├── PlatformIosTtsPlugin.swift
│   │   ├── TtsApi.g.swift
│   │   ├── KokoroTtsService.swift
│   │   ├── PiperTtsService.swift
│   │   ├── SupertonicTtsService.swift
│   │   ├── AudioConverter.swift
│   │   ├── VoiceRegistry.swift
│   │   └── ModelMemoryManager.swift
│   └── platform_ios_tts.podspec
├── lib/
│   └── platform_ios_tts.dart
├── pigeons/
│   └── tts_api.dart
├── test/
│   └── platform_ios_tts_test.dart
└── pubspec.yaml
```

### Modified Files

```
packages/tts_engines/lib/src/adapters/kokoro_adapter.dart    # Platform conditional
packages/tts_engines/lib/src/adapters/piper_adapter.dart     # Platform conditional
packages/tts_engines/lib/src/adapters/supertonic_adapter.dart # Platform conditional
ios/Podfile                                                    # Add platform_ios_tts
pubspec.yaml                                                   # Add platform_ios_tts dependency
```

---

## References

- [sherpa-onnx iOS examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)
- [ONNX Runtime iOS](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- [Flutter iOS Plugin Development](https://docs.flutter.dev/packages-and-plugins/developing-packages#swift)
- [Pigeon for Swift](https://pub.dev/packages/pigeon#swift-setup)
