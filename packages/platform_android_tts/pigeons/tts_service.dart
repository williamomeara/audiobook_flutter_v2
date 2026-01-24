// Pigeon definition for TTS native API
// Run: dart run pigeon --input pigeons/tts_service.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/generated/tts_api.g.dart',
  kotlinOut:
      'android/src/main/kotlin/com/example/platform_android_tts/generated/TtsApi.g.kt',
  kotlinOptions: KotlinOptions(
    package: 'com.example.platform_android_tts.generated',
  ),
))

/// Engine type enumeration for native side.
enum NativeEngineType {
  kokoro,
  piper,
  supertonic,
}

/// Core ready state for progress reporting.
enum NativeCoreState {
  notStarted,
  downloading,
  extracting,
  verifying,
  loaded,
  ready,
  failed,
}

/// Error codes from native synthesis.
enum NativeErrorCode {
  none,
  modelMissing,
  modelCorrupted,
  outOfMemory,
  inferenceFailed,
  cancelled,
  runtimeCrash,
  invalidInput,
  fileWriteError,
  busy,
  timeout,
  unknown,
}

/// Request to initialize an engine.
class InitEngineRequest {
  InitEngineRequest({
    required this.engineType,
    required this.corePath,
    this.configPath,
  });

  final NativeEngineType engineType;
  final String corePath;
  final String? configPath;
}

/// Request to load a voice into memory.
class LoadVoiceRequest {
  LoadVoiceRequest({
    required this.engineType,
    required this.voiceId,
    required this.modelPath,
    this.speakerId,
    this.configPath,
  });

  final NativeEngineType engineType;
  final String voiceId;
  final String modelPath;
  final int? speakerId;
  final String? configPath;
}

/// Request to synthesize text to audio.
class SynthesizeRequest {
  SynthesizeRequest({
    required this.engineType,
    required this.voiceId,
    required this.text,
    required this.outputPath,
    required this.requestId,
    this.speakerId,
    this.speed = 1.0,
  });

  final NativeEngineType engineType;
  final String voiceId;
  final String text;
  final String outputPath;
  final String requestId;
  final int? speakerId;
  final double speed;
}

/// Result of a synthesis operation.
class SynthesizeResult {
  SynthesizeResult({
    required this.success,
    this.durationMs,
    this.sampleRate,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final int? durationMs;
  final int? sampleRate;
  final NativeErrorCode? errorCode;
  final String? errorMessage;
}

/// Memory info from native side.
class MemoryInfo {
  MemoryInfo({
    required this.availableMB,
    required this.totalMB,
    required this.loadedModelCount,
  });

  final int availableMB;
  final int totalMB;
  final int loadedModelCount;
}

/// Core status information.
class CoreStatus {
  CoreStatus({
    required this.engineType,
    required this.state,
    this.errorMessage,
    this.downloadProgress,
  });

  final NativeEngineType engineType;
  final NativeCoreState state;
  final String? errorMessage;
  final double? downloadProgress;
}

/// Host API for TTS operations (Dart calls Kotlin).
@HostApi()
abstract class TtsNativeApi {
  /// Initialize an engine with its core model files.
  @async
  void initEngine(InitEngineRequest request);

  /// Load a specific voice into memory.
  @async
  void loadVoice(LoadVoiceRequest request);

  /// Synthesize text to a WAV file.
  @async
  SynthesizeResult synthesize(SynthesizeRequest request);

  /// Cancel an in-flight synthesis operation.
  @async
  void cancelSynthesis(String requestId);

  /// Unload a voice to free memory.
  @async
  void unloadVoice(NativeEngineType engineType, String voiceId);

  /// Unload all voices for an engine.
  @async
  void unloadEngine(NativeEngineType engineType);

  /// Get current memory information.
  @async
  MemoryInfo getMemoryInfo();

  /// Get core status for an engine.
  @async
  CoreStatus getCoreStatus(NativeEngineType engineType);

  /// Check if a voice is loaded and ready.
  @async
  bool isVoiceReady(NativeEngineType engineType, String voiceId);

  /// Dispose all resources.
  @async
  void dispose();
}

/// Flutter API for callbacks from native (Kotlin calls Dart).
@FlutterApi()
abstract class TtsFlutterApi {
  /// Called when synthesis progress updates.
  void onSynthesisProgress(String requestId, double progress);

  /// Called when core state changes (downloading, etc).
  void onCoreStateChanged(CoreStatus status);

  /// Called when an engine encounters an error.
  void onEngineError(NativeEngineType engineType, NativeErrorCode code, String message);
}
