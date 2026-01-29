# TTS Implementation Strategy - Improved & Complete

**Status:** Production-ready implementation plan for Piper / Kokoro / Supertonic
**Target Platforms:** Android first, iOS later
**Duration:** 4-5 weeks (10 phases)
**Architecture:** Clean separation between Dart (tts_engines) and native (platform_android)

---

## 0. DECISION MATRIX (FILL THIS FIRST)

**Before starting Phase 1, lock these decisions:**

```
PROCESS MODEL:
□ Multi-process (Option B) - Each engine in own process (:kokoro, :piper, etc)
  Decision driver: Run Model Coexistence Test (Section 1.1) - takes 30 min
  
AUDIO FORMAT:
□ Target sample rate: 24000 Hz (recommended - sweet spot for quality/size)


MODEL CACHING:
□ Low-end device (4GB): Keep 1 model loaded max


FIRST ENGINE:
□ Kokoro (recommended - simpler, fewer dependencies)
□ Piper (requires phonemizer toolchain - must be ready first)
□ Supertonic (wait until after 2 engines working)
Implement all three

ERROR RECOVERY:
□ Model missing: Auto-download now + show UI progress
□ Inference fails (OOM): Unload least-used model, retry once
□ Native runtime crash: Rebind + retry once (max)

VOICE SELECTION:
□ Voices: Select 2-3 for testing (e.g., kokoro-af, kokoro-en, en_GB-alan)
□ Model files: Pre-stage in test fixtures or host on CDN
```

---

## 1. UPFRONT RISK MITIGATION (Do These First - 2-3 Hours)

### 1.1 Model Coexistence Test (30 min)
**Location:** `packages/platform_android/android/src/test/kotlin/ModelCompatibilityTest.kt`

**Goal:** Decide: Single process (Option A) or multi-process (Option B)?

```kotlin
@RunWith(AndroidJUnit4::class)
class ModelCompatibilityTest {
    
    @Test
    fun testKokoroAndPiperCoexistence() {
        // Load Kokoro model
        val kokoro = KokoroModel.load(getContext(), "kokoro_int8")
        val kokoroResult = kokoro.synthesize("test", "af")
        
        // Load Piper model
        val piper = PiperModel.load(getContext(), "en_GB-alan-medium")
        val piperResult = piper.synthesize("test")
        
        // Both should work without crashes/conflicts
        assertTrue(kokoroResult.isNotEmpty())
        assertTrue(piperResult.isNotEmpty())
    }
    
    @Test
    fun testMemoryUsageAfterModelLoad() {
        val kokoro = KokoroModel.load(getContext(), "kokoro_int8")
        val memBefore = Runtime.getRuntime().totalMemory()
        
        kokoro.synthesize("hello world", "af")
        
        val memAfter = Runtime.getRuntime().totalMemory()
        val delta = memAfter - memBefore
        
        println("Memory delta: ${delta / (1024 * 1024)}MB")
        // Expect: <300MB for INT8, <800MB for FP32
    }
}
```

**Outcome:**
- ✅ No crashes, memory OK → Use Option A (single process, simpler)
- ❌ Crash or >1GB memory → Use Option B (multi-process, plan now)

### 1.2 Audio Format Validation (30 min)
**Location:** `test/audio_format_validation_test.dart`

**Goal:** Confirm audio output is valid and playable

```dart
import 'package:audiobook_flutter/utils/wav_parser.dart';

void main() {
  group('Audio Format Validation', () {
    test('Kokoro produces valid mono 24kHz WAV', () async {
      final adapter = KokoroAdapter();
      await adapter.ensureCoreReady('af');
      
      final request = SegmentSynthRequest(
        segmentId: 'test-1',
        normalizedText: 'Hello world, this is a test.',
        voiceId: 'af',
        outputFile: File('test_output.wav'),
      );
      
      final result = await adapter.synthesizeSegment(request);
      
      expect(result.success, true);
      expect(await request.outputFile.exists(), true);
      
      // Parse WAV header
      final wav = WavFile(await request.outputFile.readAsBytes());
      expect(wav.sampleRate, 24000);
      expect(wav.channels, 1); // mono
      expect(wav.bitsPerSample, 16);
      expect(wav.duration.inMilliseconds, greaterThan(500));
      
      // Try playing via just_audio
      final player = AudioPlayer();
      await player.setFilePath(request.outputFile.path);
      await player.play();
      await Future.delayed(Duration(seconds: 2));
      await player.stop();
      
      print('✅ Audio format valid and playable');
    });
  });
}
```

**Outcome:** Confirms:
- WAV header is correct (mono, 16-bit, 24000 Hz)
- File is playable by just_audio
- Duration > 0ms (not empty)

### 1.3 Cancellation Safety Test (30 min)
**Location:** `test/cancellation_safety_test.dart`

**Goal:** Verify cancellation doesn't corrupt cache

```dart
void main() {
  group('Cancellation Safety', () {
    test('Cancel mid-synthesis leaves no partial files', () async {
      final adapter = KokoroAdapter();
      await adapter.ensureCoreReady('af');
      
      final requests = <Future<SynthResult>>[];
      final opIds = <String>[];
      
      // Start 5 syntheses
      for (int i = 0; i < 5; i++) {
        final req = SegmentSynthRequest(
          segmentId: 'cancel-test-$i',
          normalizedText: 'This is a longer sentence to ensure synthesis takes time.',
          voiceId: 'af',
          outputFile: File('cache/test_$i.wav'),
        );
        
        final future = adapter.synthesizeSegment(req);
        requests.add(future);
        opIds.add(req.opId);
      }
      
      // Cancel after 50ms
      await Future.delayed(Duration(milliseconds: 50));
      for (final opId in opIds) {
        adapter.cancel(opId);
      }
      
      // Wait for all to complete
      final results = await Future.wait(requests, eagerError: false);
      
      // Check: cancelled requests should have no file (or be deleted)
      for (int i = 0; i < results.length; i++) {
        final file = File('cache/test_$i.wav');
        if (opIds[i] was cancelled) {
          expect(await file.exists(), false, 
            reason: 'Cancelled request should not leave partial file');
        }
      }
      
      print('✅ Cancellation is safe, no partial files remain');
    });
  });
}
```

**Outcome:** Confirms cancellation protocol is safe

---

## 2. ARCHITECTURE (State Machines & APIs)

### 2.1 Core Ready State Machine

```dart
enum CoreReadyState {
  notStarted,       // Core not checked yet
  downloading,      // Fetching core from CDN
  extracting,       // Unpacking tar.gz
  verifying,        // Checking SHA256
  loaded,           // Model loaded in memory
  ready,            // Ready to synthesize
  failed,           // Permanent error (user action needed)
}

class CoreReadiness {
  final CoreReadyState state;
  final String? engineId;
  final String? errorMessage;
  final double? downloadProgress; // 0.0 to 1.0 during download
  
  bool get isReady => state == CoreReadyState.ready;
  bool get canSynthesizeNow => state == CoreReadyState.loaded || state == CoreReadyState.ready;
}
```

**Transitions:**
```
notStarted
  → downloading (user clicks voice)
  → extracting (download complete)
  → verifying (extraction complete)
  → loaded (verification ok)
  → ready (first synth requested)
  
(any) → failed (error at any stage)

failed → downloading (user clicks retry)
```

### 2.2 Voice Ready State Machine

```dart
enum VoiceReadyState {
  checking,         // Checking if voice is ready
  coreRequired,     // Core must download first
  coreLoading,      // Core is loading
  voiceReady,       // Ready to synthesize
  error,            // Permanent error
}

class VoiceReadiness {
  final VoiceId voiceId;
  final VoiceReadyState state;
  final CoreReadyState? coreState;
  final String? nextActionUserShouldTake; // e.g., "Download core (250MB)"
}
```

### 2.3 Synthesis Lifecycle

```dart
class SegmentSynthRequest {
  final String opId;  // Unique operation ID
  final SegmentId segmentId;
  final String normalizedText;
  final VoiceId voiceId;
  final File outputFile;
  final Duration timeout = Duration(seconds: 30);
  
  // New fields
  CancelToken? cancelToken;  // For cancellation
  int retryAttempt = 0;
  int maxRetries = 1;
}

enum SynthStage {
  queued,           // Waiting for synth pool
  voiceReady,       // Checking voice is loaded
  inferencing,      // Running model
  writingFile,      // Writing WAV to disk
  cacheMoving,      // Moving from .tmp to final
  complete,         // Success
  failed,           // Error
  cancelled,        // User cancelled
}

class SynthResult {
  final bool success;
  final File? outputFile;
  final Duration? duration;
  final String? errorMessage;
  final SynthStage? stage; // Where it failed
  final int retryCount;
}
```

### 2.4 Platform Channel Contract (Using Pigeon)

**File:** `packages/platform_android/pigeons/tts_service.dart`

```dart
@HostApi()
abstract class TtsNativeApi {
  /// Initialize engine (load runtime, setup)
  Future<void> initEngine(String engineType, String corePath);
  
  /// Load a specific voice (load model files into memory)
  Future<void> loadVoice(
    String engineType,
    String voiceId,
    String modelPath,
    String? configPath,
  );
  
  /// Synthesize and write to file
  /// Returns: {success, durationMs, errorCode, errorMessage}
  Future<Map<String, Object?>> synthesize(
    String engineType,
    String voiceId,
    String normalizedText,
    String outputWavPath,
    String requestId,
  );
  
  /// Cancel an in-flight synthesis
  Future<void> cancelSynth(String requestId);
  
  /// Unload voice to free memory
  Future<void> unloadVoice(String engineType, String voiceId);
  
  /// Check memory available
  Future<int> getAvailableMemoryMB();
  
  /// Dispose engine (cleanup)
  Future<void> disposeEngine(String engineType);
}
```

**Pigeon generates:**
- `platform_android/android/src/main/kotlin/GeneratedTtsApi.kt`
- `lib/platform_android_generated.dart` (Dart stubs)

---

## 3. ASSET ORGANIZATION & DOWNLOADS

### 3.1 Disk Layout (Immutable, Atomic)

```
app_files/
├── voice_assets/
│   ├── cores/
│   │   ├── kokoro_fp32_v1/
│   │   │   ├── model.onnx
│   │   │   ├── config.json
│   │   │   └── .manifest (metadata: version, hash, size)
│   │   ├── kokoro_int8_v1/
│   │   ├── piper_generic_v1/
│   │   └── espeak_ng_data_v1/
│   └── voices/
│       ├── kokoro-af/
│       │   └── .manifest (references: kokoro_int8, espeak_ng_data)
│       └── en_GB-alan-medium/
│           └── .manifest (references: piper_generic)
└── synth_cache/
    ├── kokoro-af_[hash].wav
    ├── en_GB-alan-medium_[hash].wav
    └── .lru_index (last access times)
```

### 3.2 Download & Install Atomicity

**Never corrupt cache. Use .tmp pattern:**

```dart
Future<void> downloadAndExtractCore(AssetSpec spec) async {
  final targetDir = Directory(coreDir.path + spec.coreId);
  final tmpDir = Directory(coreDir.path + spec.coreId + '.tmp');
  final tmpTarGz = File(tmpDir.path + '.tar.gz.tmp');
  
  try {
    // Phase 1: Download to .tmp
    await tmpTarGz.parent.create(recursive: true);
    await _downloadWithResumeAndVerify(spec.url, tmpTarGz, spec.sha256);
    
    // Phase 2: Extract to .tmp directory
    await tmpDir.create(recursive: true);
    await _extractTarGz(tmpTarGz, tmpDir);
    
    // Phase 3: Verify extraction integrity
    await _verifyExtraction(tmpDir, spec.expectedFileList);
    
    // Phase 4: Atomic rename (swap tmp → real)
    if (await targetDir.exists()) {
      await targetDir.rename(targetDir.path + '.old');
    }
    await tmpDir.rename(targetDir.path);
    
    // Phase 5: Write manifest + cleanup old
    await _writeManifest(targetDir, spec);
    await Directory(targetDir.path + '.old').delete(recursive: true);
    
  } catch (e) {
    // Clean up .tmp on any failure
    await tmpDir.delete(recursive: true);
    await tmpTarGz.delete();
    rethrow;
  }
}
```

### 3.3 VoiceManifest (JSON at Boot)

**File:** `packages/downloads/lib/manifests/voices_manifest.json`

```json
{
  "version": 1,
  "voices": [
    {
      "id": "kokoro-af",
      "displayName": "Kokoro (Afrikaans)",
      "engineId": "kokoro",
      "language": "af",
      "coreRequirements": [
        {
          "coreId": "kokoro_int8_v1",
          "url": "https://cdn.example.com/kokoro_int8_v1.tar.gz",
          "sizeBytes": 250000000,
          "sha256": "abc123...",
          "required": true
        },
        {
          "coreId": "espeak_ng_data_v1",
          "url": "https://cdn.example.com/espeak_ng_data_v1.tar.gz",
          "sizeBytes": 50000000,
          "sha256": "def456...",
          "required": true
        }
      ],
      "preferredQuality": "int8",
      "estimatedSynthTimeMs": 1500
    },
    {
      "id": "en_GB-alan-medium",
      "displayName": "Piper (Alan - GB)",
      "engineId": "piper",
      "language": "en",
      "coreRequirements": [
        {
          "coreId": "piper_generic_v1",
          "url": "https://cdn.example.com/piper_generic_v1.tar.gz",
          "sizeBytes": 50000000,
          "sha256": "ghi789...",
          "required": true
        }
      ]
    }
  ]
}
```

---

## 4. PHASE-BY-PHASE IMPLEMENTATION (10 Phases, 4-5 Weeks)

### Phase 1: Upfront Tests + Decisions (Days 1-2)

**Tasks:**
- [ ] Run Model Coexistence Test (1.1)
- [ ] Run Audio Format Validation (1.2)
- [ ] Run Cancellation Safety Test (1.3)
- [ ] Fill Decision Matrix (Section 0)
- [ ] Create test fixtures directory
- [ ] Sketch native module structure

**Deliverables:**
- [ ] Decision matrix completed
- [ ] Risk mitigation tests passing
- [ ] Go/no-go decision on Option A vs Option B

---

### Phase 2: Dart-Side TTS Engine Interface (Days 3-4)

**Location:** `packages/tts_engines/`

**Files to create:**

#### 2.1 Update TtsEngine interface

**File:** `lib/interfaces/tts_engine.dart`

```dart
enum EngineError {
  modelMissing,      // Core not installed
  modelCorrupted,    // SHA256 mismatch
  inferenceFailed,   // Model inference error (OOM, etc)
  runtimeCrash,      // Native runtime crashed
  cancelled,         // User cancelled operation
}

abstract interface class TtsEngine {
  EngineId get id;
  Future<EngineProbe> probe();
  
  // New: explicit core ready lifecycle
  Future<CoreReadiness> ensureCoreReady(VoiceId voiceId);
  Stream<CoreReadiness> watchCoreReadiness(String coreId);
  
  // New: explicit voice ready check
  Future<VoiceReadiness> checkVoiceReady(VoiceId voiceId);
  
  // Synthesis with cancellation
  Future<SynthResult> synthesizeSegment(SegmentSynthRequest request);
  Future<void> cancelSynth(String requestId);
  
  // Memory management
  Future<int> getLoadedModelCount();
  Future<void> unloadLeastUsedModel();
  Future<void> clearAllModels();
}
```

#### 2.2 Create concrete adapter classes

**File:** `lib/adapters/kokoro_adapter.dart`

```dart
class KokoroAdapter implements TtsEngine {
  final PlatformChannel _channel;
  final AssetManager _assetManager;
  final DeviceProfile _device;
  
  KokoroAdapter(this._channel, this._assetManager, this._device);
  
  @override
  Future<CoreReadiness> ensureCoreReady(VoiceId voiceId) async {
    // 1. Check if core already loaded
    try {
      final status = await _channel.getCoreStatus('kokoro');
      if (status['isReady'] == true) {
        return CoreReadiness(state: CoreReadyState.ready, engineId: 'kokoro');
      }
    } catch (_) {}
    
    // 2. Check if core installed locally
    final coreId = _selectCoreVariant(voiceId);
    final coreDir = _assetManager.getCoreDir(coreId);
    
    if (!await coreDir.exists()) {
      // 3. Trigger download
      return _downloadAndInstallCore(coreId);
    }
    
    // 4. Core exists, load it
    await _channel.initEngine('kokoro', coreDir.path);
    return CoreReadiness(state: CoreReadyState.loaded, engineId: 'kokoro');
  }
  
  String _selectCoreVariant(VoiceId voiceId) {
    // Kokoro voices share core; select by device profile
    final quality = _device.preferredQuality();
    return 'kokoro_${quality.name}_v1';
  }
  
  Future<SynthResult> synthesizeSegment(SegmentSynthRequest request) async {
    try {
      // Ensure voice ready
      final readiness = await checkVoiceReady(request.voiceId);
      if (!readiness.state == VoiceReadyState.voiceReady) {
        return SynthResult(
          success: false,
          errorMessage: 'Voice not ready: ${readiness.nextActionUserShouldTake}',
          stage: SynthStage.voiceReady,
        );
      }
      
      // Call native synth
      final result = await _channel.synthesize(
        engineType: 'kokoro',
        voiceId: request.voiceId,
        normalizedText: request.normalizedText,
        outputWavPath: request.outputFile.path,
        requestId: request.opId,
      );
      
      if (result['success'] != true) {
        final errorCode = result['errorCode'];
        return _handleSynthError(errorCode, result['errorMessage']);
      }
      
      return SynthResult(
        success: true,
        outputFile: request.outputFile,
        duration: Duration(milliseconds: result['durationMs'] as int? ?? 0),
      );
    } on PlatformException catch (e) {
      return _handlePlatformError(e);
    }
  }
  
  SynthResult _handleSynthError(String? code, String? msg) {
    // Map error codes to recovery policies
    switch (code) {
      case 'MODEL_MISSING':
        return SynthResult(success: false, errorMessage: 'Model missing');
      case 'OUT_OF_MEMORY':
        // Unload least-used model and retry
        unawaited(unloadLeastUsedModel());
        return SynthResult(success: false, errorMessage: 'OOM, retrying...');
      default:
        return SynthResult(success: false, errorMessage: msg ?? 'Unknown error');
    }
  }
}
```

#### 2.3 Create SynthesisPool update

**File:** `lib/synthesis_pool.dart`

```dart
class SynthesisPool {
  final Map<CacheKey, Future<File>> _pending = {};
  final List<SegmentSynthRequest> _cancellationQueue = [];
  
  Future<File> enqueue(SegmentSynthRequest request) {
    final key = request.cacheKey;
    
    if (_pending.containsKey(key)) {
      // Return existing future
      return _pending[key]!;
    }
    
    final completer = Completer<File>();
    _pending[key] = completer.future;
    
    _synthesizeInBackground(request).then((file) {
      completer.complete(file);
    }).catchError((e) {
      completer.completeError(e);
    }).whenComplete(() {
      _pending.remove(key);
      _cancellationQueue.removeWhere((r) => r.opId == request.opId);
    });
    
    return completer.future;
  }
  
  void cancel(String opId) {
    final req = _cancellationQueue.firstWhereOrNull((r) => r.opId == opId);
    if (req != null) {
      _engine.cancelSynth(opId);
    }
  }
}
```

**Checklist:**
- [ ] TtsEngine interface updated with state machines
- [ ] KokoroAdapter implemented (without native calls)
- [ ] PiperAdapter stub created
- [ ] SupertonicAdapter stub created
- [ ] SynthesisPool updated with cancellation support
- [ ] Tests: Interface contracts verified

---

### Phase 3: Native Layer Setup (Days 5-7)

**Location:** `packages/platform_android/android/src/main/`

#### 3.1 Define AIDL / Pigeon contracts

Generate via Pigeon (see Section 2.4 above)

**Command:**
```bash
flutter pub run pigeon \
  --input pigeons/tts_service.dart \
  --dart_out lib/generated_tts_api.dart \
  --kotlin_out android/src/main/kotlin/com/audiobook/tts/GeneratedTtsApi.kt
```

#### 3.2 Create Kokoro Native Service

**File:** `android/src/main/kotlin/com/audiobook/tts/KokoroTtsService.kt`

```kotlin
class KokoroTtsService : TtsNativeApi {
  private var model: KokoroModel? = null
  private var voiceId: String? = null
  private val synthesisJobs = mutableMapOf<String, Job>()
  
  override suspend fun initEngine(engineType: String, corePath: String) {
    if (model != null) return
    
    val modelPath = "$corePath/model.onnx"
    model = KokoroModel.load(modelPath)
  }
  
  override suspend fun loadVoice(
    engineType: String,
    voiceId: String,
    modelPath: String,
    configPath: String?
  ) {
    // Kokoro: voice ID is runtime parameter, not a separate file
    this.voiceId = voiceId
  }
  
  override suspend fun synthesize(
    engineType: String,
    voiceId: String,
    normalizedText: String,
    outputWavPath: String,
    requestId: String
  ): Map<String, Any?> {
    val model = model ?: return mapOf(
      "success" to false,
      "errorCode" to "MODEL_MISSING",
      "errorMessage" to "Kokoro model not initialized"
    )
    
    return withContext(Dispatchers.Default) {
      val tmpPath = "$outputWavPath.tmp"
      
      try {
        // Run on background thread
        val audio = model.synthesize(normalizedText, voiceId)
        
        // Write to temp file
        File(tmpPath).outputStream().use { os ->
          writeWavHeader(os, audio.sampleRate, audio.samples.size)
          audio.samples.forEach { sample ->
            os.write((sample and 0xFF).toByte().toInt())
            os.write(((sample shr 8) and 0xFF).toByte().toInt())
          }
        }
        
        // Atomic rename
        File(tmpPath).renameTo(File(outputWavPath))
        
        mapOf(
          "success" to true,
          "durationMs" to (audio.samples.size * 1000 / audio.sampleRate)
        )
      } catch (e: Exception) {
        File(tmpPath).delete()
        mapOf(
          "success" to false,
          "errorCode" to when (e) {
            is OutOfMemoryError -> "OUT_OF_MEMORY"
            else -> "INFERENCE_FAILED"
          },
          "errorMessage" to e.message
        )
      }
    }
  }
  
  override suspend fun cancelSynth(requestId: String) {
    synthesisJobs[requestId]?.cancel()
    synthesisJobs.remove(requestId)
    
    // Delete partial file if exists
    File("${/* output path from context */}.tmp").delete()
  }
  
  override suspend fun getAvailableMemoryMB(): Int {
    val runtime = Runtime.getRuntime()
    return ((runtime.maxMemory() - runtime.totalMemory()) / (1024 * 1024)).toInt()
  }
  
  override suspend fun disposeEngine(engineType: String) {
    model = null
    synthesisJobs.clear()
  }
}
```

**Checklist:**
- [ ] Pigeon generates Dart + Kotlin stubs
- [ ] KokoroTtsService implements TtsNativeApi
- [ ] Cancellation deletes .tmp files
- [ ] WAV header written correctly (16-bit, mono)
- [ ] Memory management (return available MB)
- [ ] Tests: Native synthesis produces valid WAV

---

### Phase 4: Bridge Kotlin ↔ Dart (Days 8-9)

**File:** `lib/adapters/kokoro_adapter_native.dart`

```dart
class KokoroAdapterNative implements TtsEngine {
  static const _channel = MethodChannel('com.audiobook/tts');
  
  @override
  Future<SynthResult> synthesizeSegment(SegmentSynthRequest request) async {
    try {
      final result = await _channel.invokeMethod('synthesize', {
        'engineType': 'kokoro',
        'voiceId': request.voiceId,
        'normalizedText': request.normalizedText,
        'outputWavPath': request.outputFile.path,
        'requestId': request.opId,
      });
      
      if (result['success'] != true) {
        return SynthResult(
          success: false,
          errorMessage: result['errorMessage'],
        );
      }
      
      return SynthResult(
        success: true,
        outputFile: request.outputFile,
        duration: Duration(milliseconds: result['durationMs']),
      );
    } on PlatformException catch (e) {
      // Handle rebind + retry
      return _handlePlatformError(e, request);
    }
  }
  
  Future<SynthResult> _handlePlatformError(
    PlatformException e,
    SegmentSynthRequest request,
  ) async {
    if (e.code == 'SERVICE_DEAD') {
      // Service crashed, retry once
      if (request.retryAttempt < 1) {
        await Future.delayed(Duration(milliseconds: 100));
        request.retryAttempt++;
        return synthesizeSegment(request);
      }
    }
    
    return SynthResult(success: false, errorMessage: e.message);
  }
}
```

**Checklist:**
- [ ] MethodChannel communication working
- [ ] Error codes mapped to recovery actions
- [ ] Retry logic for SERVICE_DEAD
- [ ] Tests: Native → Dart communication verified

---

### Phase 5: Asset Pipeline Integration (Days 10-12)

**Update:** `packages/downloads/lib/impl/voice_asset_manager.dart`

```dart
Future<void> ensureVoiceReady(VoiceId voiceId) async {
  final voiceSpec = _manifest.voices.firstWhere((v) => v.id == voiceId);
  
  for (final coreReq in voiceSpec.coreRequirements) {
    final coreDir = _getCoreDir(coreReq.coreId);
    
    if (!await coreDir.exists()) {
      // Download and install atomically
      await _downloadAndInstallCore(coreReq);
    } else {
      // Verify manifest
      final manifest = await _readManifest(coreDir);
      if (manifest.sha256 != coreReq.sha256) {
        // Corrupted, re-download
        await coreDir.delete(recursive: true);
        await _downloadAndInstallCore(coreReq);
      }
    }
  }
}

Future<void> _downloadAndInstallCore(CoreRequirement coreReq) async {
  final tmpDir = Directory(_getCoreDir(coreReq.coreId).path + '.tmp');
  final tmpTarGz = File(tmpDir.path + '.tar.gz');
  
  try {
    await tmpDir.create(recursive: true);
    
    // Download with resume + progress
    await _downloadWithResume(
      coreReq.url,
      tmpTarGz,
      onProgress: (current, total) {
        _stateStream.add(DownloadState(
          coreId: coreReq.coreId,
          status: DownloadStatus.downloading,
          downloadedBytes: current,
          totalBytes: total,
        ));
      },
    );
    
    // Verify checksum
    final hash = await _sha256File(tmpTarGz);
    if (hash != coreReq.sha256) {
      throw Exception('SHA256 mismatch');
    }
    
    // Extract
    await _extractTarGz(tmpTarGz, tmpDir);
    
    // Atomic rename
    final targetDir = _getCoreDir(coreReq.coreId);
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await tmpDir.rename(targetDir.path);
    
    // Write manifest
    await _writeManifest(targetDir, coreReq);
    
    _stateStream.add(DownloadState(
      coreId: coreReq.coreId,
      status: DownloadStatus.completed,
    ));
  } catch (e) {
    await tmpDir.delete(recursive: true);
    _stateStream.add(DownloadState(
      coreId: coreReq.coreId,
      status: DownloadStatus.failed,
      errorMessage: e.toString(),
    ));
    rethrow;
  }
}
```

**Checklist:**
- [ ] Voice manifest integrated
- [ ] Core download atomic (with .tmp pattern)
- [ ] SHA256 verification per core
- [ ] Download progress streamed to UI
- [ ] Corrupt core handling (re-download)
- [ ] Tests: Asset pipeline end-to-end

---

### Phase 6: Model Caching & Memory Management (Days 13-14)

**File:** `lib/impl/model_cache_manager.dart`

```dart
class ModelCacheManager {
  final DeviceProfile _device;
  final Map<String, LoadedModel> _loadedModels = {};
  final Queue<String> _lruQueue = Queue();
  
  Future<void> ensureModelLoaded(String engineId, String voiceId) async {
    if (_loadedModels.containsKey('$engineId:$voiceId')) {
      _lruQueue.remove('$engineId:$voiceId');
      _lruQueue.addLast('$engineId:$voiceId');
      return;
    }
    
    // Check available memory
    final availableMemory = await _getAvailableMemoryMB();
    final modelEstimate = _getModelSizeMB(engineId, voiceId);
    
    // Unload least-used models if needed
    while (availableMemory < modelEstimate + 100 && _loadedModels.isNotEmpty) {
      final leastUsed = _lruQueue.removeFirst();
      await _unloadModel(leastUsed);
    }
    
    // Load model
    await _nativeChannel.loadVoice(engineId, voiceId);
    _loadedModels['$engineId:$voiceId'] = LoadedModel(
      engineId: engineId,
      voiceId: voiceId,
      loadedAt: DateTime.now(),
    );
    _lruQueue.addLast('$engineId:$voiceId');
  }
  
  Future<void> _unloadModel(String key) async {
    final [engineId, voiceId] = key.split(':');
    await _nativeChannel.unloadVoice(engineId, voiceId);
    _loadedModels.remove(key);
  }
  
  int _getModelSizeMB(String engineId, String voiceId) {
    // Return estimated size based on engine + quality
    return switch (engineId) {
      'kokoro' => _device.preferredQuality() == Quality.fp32 ? 800 : 250,
      'piper' => 50,
      'supertonic' => 200,
      _ => 100,
    };
  }
  
  Future<int> _getAvailableMemoryMB() async {
    return await _nativeChannel.getAvailableMemoryMB();
  }
}
```

**Checklist:**
- [ ] Model loading tracked (LRU)
- [ ] Memory budget enforced
- [ ] Lazy unload on pressure
- [ ] Device profile used for decisions
- [ ] Tests: Memory management under load

---

### Phase 7: Piper Integration (Days 15-17)

**Requirements first:**
- [ ] Phonemizer toolchain ready (espeak-ng + phonemizer binary or Dart wrapper)
- [ ] Piper model files downloaded + verified

**File:** `lib/adapters/piper_adapter.dart`

```dart
class PiperAdapter implements TtsEngine {
  final PlatformChannel _channel;
  final Phonemizer _phonemizer;
  
  @override
  Future<SynthResult> synthesizeSegment(SegmentSynthRequest request) async {
    // Piper needs phonemes, not raw text
    final phonemes = await _phonemizer.phonemize(request.normalizedText);
    
    try {
      final result = await _channel.invokeMethod('synthesize', {
        'engineType': 'piper',
        'voiceId': request.voiceId,
        'phonemes': phonemes,  // Piper input
        'outputWavPath': request.outputFile.path,
        'requestId': request.opId,
      });
      
      return _parseResult(result);
    } catch (e) {
      return SynthResult(success: false, errorMessage: e.toString());
    }
  }
}
```

**Checklist:**
- [ ] Phonemizer integrated + working
- [ ] Piper native adapter ready
- [ ] Model loaded with correct speaker ID
- [ ] Tests: Piper synthesis working

---

### Phase 8: Supertonic Integration (Days 18-20)

Similar to Phase 7, but:
- [ ] Supertonic needs speaker embeddings (per-voice file)
- [ ] Style parameters (aggressiveness, etc)

**Checklist:**
- [ ] Supertonic adapter implemented
- [ ] Speaker embedding loading
- [ ] Style parameter support
- [ ] Tests: Supertonic synthesis working

---

### Phase 9: Playback Integration + Caching (Days 21-23)

**Update:** `packages/playback/lib/impl/buffer_scheduler.dart`

Connect synthesis pool → cache → playback:

```dart
void _submitSynthRequest(Segment segment) async {
  final cacheKey = CacheKey.forSegment(
    segmentId: segment.id,
    voiceId: _voiceId,
    engineId: _engineId,
    text: segment.text,
    sampleRate: 24000,  // NEW: explicit sample rate in key
  );
  
  if (await _cache.isReady(cacheKey)) {
    _activeSynthCount--;
    _scheduleAhead();
    return;
  }
  
  final request = SegmentSynthRequest(
    segmentId: segment.id,
    normalizedText: segment.text,
    voiceId: _voiceId,
    outputFile: await _cache.fileFor(cacheKey),
    opId: uuid.v4(),
  );
  
  _pool.enqueue(request).then((_) {
    _cache.markUsed(cacheKey);
    _activeSynthCount--;
    _scheduleAhead();
  }).catchError((e) {
    // Handle synth error
    _logger.error('Synth failed: $e');
    _activeSynthCount--;
    _scheduleAhead();
  });
}
```

**Checklist:**
- [ ] Synthesis integrated with cache
- [ ] Sample rate in cache key
- [ ] Playback starts when buffers ready
- [ ] Tests: End-to-end import → synth → play

---

### Phase 10: Performance Hardening + Testing (Days 24-27)

**Tests:**
- [ ] Cold synth latency <5s (Kokoro INT8)
- [ ] Warm cache hit <500ms
- [ ] Memory peak <300MB
- [ ] Cancellation safety (no partial files)
- [ ] Voice switching mid-playback
- [ ] Stress: 50 rapid synth requests

**Checklist:**
- [ ] All perf metrics pass
- [ ] Golden file tests for UI
- [ ] Integration tests pass
- [ ] Crash rate <0.1%
- [ ] Ready for release

---

## 5. PLATFORM STRATEGY (Option A vs B)

### Option A: Single Process (Recommended - Start Here)

**All engines in main process:**
```
Main App Process
├── Kokoro (if model coexistence test passes)
├── Piper (if model coexistence test passes)
└── Supertonic (if model coexistence test passes)
```

**Pros:**
- Simpler architecture
- Faster IPC (no Binder overhead)
- Easier debugging

**Cons:**
- Risk of native lib conflicts
- Memory from all models active

**Decision:** Run Section 1.1 test. If it passes, use Option A.

### Option B: Multi-Process (If Option A Conflicts)

**Separate processes per engine:**
```
Main App Process
├── :kokoro (isolated, own process)
├── :piper (isolated, own process)
└── :supertonic (isolated, own process)
```

**Pros:**
- Complete isolation
- Avoids lib conflicts

**Cons:**
- More complex IPC
- Binder overhead
- Harder to debug

**Activation:** If Section 1.1 test fails, implement:
- AndroidManifest declarations (one <service> per engine with android:process)
- Binder service routers for each engine
- MethodChannel forwarding logic
- Process death recovery

---

## 6. TESTING CHECKPOINTS (Per Phase)

```
Phase 1: ✅ Decisions locked + risk tests passing
Phase 2: ✅ TtsEngine interface contracts verified
Phase 3: ✅ Native module compiles, Pigeon stubs working
Phase 4: ✅ Kokoro native → Dart bridge tested
Phase 5: ✅ Asset pipeline: download → extract → verify
Phase 6: ✅ Model memory management under load
Phase 7: ✅ Piper phonemizer + inference working
Phase 8: ✅ Supertonic speaker embeddings loaded
Phase 9: ✅ Playback buffer scheduler + cache integrated
Phase 10: ✅ Performance targets met + stress tests pass
```

---

## 7. KNOWN RISKS & MITIGATION

| Risk | Mitigation |
|------|-----------|
| **Native lib conflicts** | Section 1.1 test (30 min) decides architecture |
| **Audio format mismatch** | Section 1.2 validation (early) |
| **Cancellation race conditions** | .tmp file protocol + atomic rename |
| **Memory bloat (4GB devices)** | LRU model unload + device profile |
| **Piper phonemizer unavailable** | Phase 2 resolve before Phase 7 start |
| **Model corruption on failed download** | Atomic .tmp → rename |
| **Native runtime crash** | Binder death detection + rebind+retry |
| **Sample rate mismatch** | Explicit in cache key |

---

## 8. QUICK START CHECKLIST

Before Phase 1 Day 1:

- [ ] Clone repo
- [ ] Verify build works (`flutter build apk` on stub)
- [ ] Identify test devices (4GB low-end, 12GB high-end if possible)
- [ ] Prepare model files (or download links)
- [ ] Notify team: TTS implementation starting (4-5 weeks)

**Phase 1 Day 1:**
- [ ] Run upfront tests (Section 1)
- [ ] Fill decision matrix (Section 0)
- [ ] Commit decisions to DECISION.md

**Phase 1 Day 2:**
- [ ] Plan Option A or B architecture (based on test results)
- [ ] Start Phase 2

---

## 9. ARCHITECTURE DIAGRAM (Option A)

```
┌─────────────────────────────────────────┐
│         Flutter App (Dart)              │
│  ┌──────────────────────────────────┐   │
│  │ UI: Voice Selection + Playback   │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ PlaybackController +             │   │
│  │ BufferScheduler + SynthesisPool  │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ TtsEngines (Kokoro/Piper/Super)  │   │
│  │ Adapters dispatch to platform    │   │
│  └──────────────────────────────────┘   │
└────────────────┬────────────────────────┘
                 │ MethodChannel
                 ▼
┌─────────────────────────────────────────┐
│       Android Native (Kotlin)           │
│  ┌──────────────────────────────────┐   │
│  │ TtsNativeApi (Pigeon generated)  │   │
│  │ synthesize() / cancel()          │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ KokoroTtsService                 │   │
│  │ load model → synthesize → WAV    │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ PiperTtsService                  │   │
│  │ + phonemizer                     │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ SupertonicTtsService             │   │
│  │ + speaker embeddings             │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

---

**Next:** Share this with your AI agent + start Phase 1!
