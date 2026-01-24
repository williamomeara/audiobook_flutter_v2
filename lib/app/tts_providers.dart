import 'dart:io';

import 'package:flutter/services.dart' show BinaryMessenger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';
import 'package:platform_android_tts/platform_android_tts.dart' as android;
import 'package:platform_ios_tts/platform_ios_tts.dart' as ios;

import 'app_paths.dart';
import 'granular_download_manager.dart';
import 'playback_providers.dart';

/// Provider for TTS Native API (Pigeon-generated).
/// Returns the platform-appropriate API (Android or iOS).
final ttsNativeApiProvider = Provider<android.TtsNativeApi>((ref) {
  if (Platform.isIOS) {
    // iOS uses its own TtsNativeApi - we wrap it for type compatibility
    return _IosApiWrapper(ios.TtsNativeApi());
  }
  return android.TtsNativeApi();
});

/// Wrapper to adapt iOS TtsNativeApi to Android TtsNativeApi type.
/// Both APIs have identical signatures (Pigeon-generated from same definition).
class _IosApiWrapper implements android.TtsNativeApi {
  final ios.TtsNativeApi _iosApi;

  _IosApiWrapper(this._iosApi);

  @override
  String get pigeonVar_messageChannelSuffix => '';

  @override
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  Future<void> initEngine(android.InitEngineRequest request) async {
    final iosRequest = ios.InitEngineRequest(
      engineType: _toIosEngineType(request.engineType),
      corePath: request.corePath,
      configPath: request.configPath,
    );
    await _iosApi.initEngine(iosRequest);
  }

  @override
  Future<void> loadVoice(android.LoadVoiceRequest request) async {
    final iosRequest = ios.LoadVoiceRequest(
      engineType: _toIosEngineType(request.engineType),
      voiceId: request.voiceId,
      modelPath: request.modelPath,
      speakerId: request.speakerId,
      configPath: request.configPath,
    );
    await _iosApi.loadVoice(iosRequest);
  }

  @override
  Future<android.SynthesizeResult> synthesize(android.SynthesizeRequest request) async {
    final iosRequest = ios.SynthesizeRequest(
      engineType: _toIosEngineType(request.engineType),
      voiceId: request.voiceId,
      text: request.text,
      outputPath: request.outputPath,
      requestId: request.requestId,
      speakerId: request.speakerId,
      speed: request.speed,
    );
    final iosResult = await _iosApi.synthesize(iosRequest);
    return android.SynthesizeResult(
      success: iosResult.success,
      durationMs: iosResult.durationMs,
      sampleRate: iosResult.sampleRate,
      errorCode: _fromIosErrorCode(iosResult.errorCode),
      errorMessage: iosResult.errorMessage,
    );
  }

  @override
  Future<void> cancelSynthesis(String requestId) async {
    await _iosApi.cancelSynthesis(requestId);
  }

  @override
  Future<void> unloadVoice(android.NativeEngineType engineType, String voiceId) async {
    await _iosApi.unloadVoice(_toIosEngineType(engineType), voiceId);
  }

  @override
  Future<void> unloadEngine(android.NativeEngineType engineType) async {
    await _iosApi.unloadEngine(_toIosEngineType(engineType));
  }

  @override
  Future<android.MemoryInfo> getMemoryInfo() async {
    final iosInfo = await _iosApi.getMemoryInfo();
    return android.MemoryInfo(
      availableMB: iosInfo.availableMB,
      totalMB: iosInfo.totalMB,
      loadedModelCount: iosInfo.loadedModelCount,
    );
  }

  @override
  Future<android.CoreStatus> getCoreStatus(android.NativeEngineType engineType) async {
    final iosStatus = await _iosApi.getCoreStatus(_toIosEngineType(engineType));
    return android.CoreStatus(
      engineType: engineType,
      state: _fromIosCoreState(iosStatus.state),
      downloadProgress: iosStatus.downloadProgress,
      errorMessage: iosStatus.errorMessage,
    );
  }

  @override
  Future<bool> isVoiceReady(android.NativeEngineType engineType, String voiceId) async {
    return await _iosApi.isVoiceReady(_toIosEngineType(engineType), voiceId);
  }

  @override
  Future<void> dispose() async {
    await _iosApi.dispose();
  }

  // Type conversions between Android and iOS enums

  ios.NativeEngineType _toIosEngineType(android.NativeEngineType type) {
    return switch (type) {
      android.NativeEngineType.kokoro => ios.NativeEngineType.kokoro,
      android.NativeEngineType.piper => ios.NativeEngineType.piper,
      android.NativeEngineType.supertonic => ios.NativeEngineType.supertonic,
    };
  }

  android.NativeErrorCode? _fromIosErrorCode(ios.NativeErrorCode? code) {
    if (code == null) return null;
    return switch (code) {
      ios.NativeErrorCode.none => android.NativeErrorCode.none,
      ios.NativeErrorCode.modelMissing => android.NativeErrorCode.modelMissing,
      ios.NativeErrorCode.modelCorrupted => android.NativeErrorCode.modelCorrupted,
      ios.NativeErrorCode.outOfMemory => android.NativeErrorCode.outOfMemory,
      ios.NativeErrorCode.inferenceFailed => android.NativeErrorCode.inferenceFailed,
      ios.NativeErrorCode.cancelled => android.NativeErrorCode.cancelled,
      ios.NativeErrorCode.runtimeCrash => android.NativeErrorCode.runtimeCrash,
      ios.NativeErrorCode.invalidInput => android.NativeErrorCode.invalidInput,
      ios.NativeErrorCode.fileWriteError => android.NativeErrorCode.fileWriteError,
      ios.NativeErrorCode.busy => android.NativeErrorCode.busy,
      ios.NativeErrorCode.timeout => android.NativeErrorCode.timeout,
      ios.NativeErrorCode.unknown => android.NativeErrorCode.unknown,
    };
  }

  android.NativeCoreState _fromIosCoreState(ios.NativeCoreState state) {
    return switch (state) {
      ios.NativeCoreState.notStarted => android.NativeCoreState.notStarted,
      ios.NativeCoreState.downloading => android.NativeCoreState.downloading,
      ios.NativeCoreState.extracting => android.NativeCoreState.extracting,
      ios.NativeCoreState.verifying => android.NativeCoreState.verifying,
      ios.NativeCoreState.loaded => android.NativeCoreState.loaded,
      ios.NativeCoreState.ready => android.NativeCoreState.ready,
      ios.NativeCoreState.failed => android.NativeCoreState.failed,
    };
  }
}

/// Provider for Kokoro adapter.
/// Checks granular download state to see if required cores are ready.
/// Uses watch to reactively update when downloads complete.
final kokoroAdapterProvider = FutureProvider<KokoroAdapter?>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final granularState = await ref.watch(granularDownloadManagerProvider.future);
  
  // Check if Kokoro core is ready via granular system
  final isReady = granularState.cores['kokoro_core_v1']?.isReady ?? false;
  
  if (!isReady) return null;

  final nativeApi = ref.read(ttsNativeApiProvider);
  return KokoroAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for Piper adapter.
/// Piper voices are per-model cores, check if any Piper core is ready.
/// Uses watch to reactively update when downloads complete.
final piperAdapterProvider = FutureProvider<PiperAdapter?>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final granularState = await ref.watch(granularDownloadManagerProvider.future);
  
  // Check if any Piper core is ready
  final piperCores = granularState.cores.values.where((c) => c.engineType == 'piper');
  final isReady = piperCores.any((c) => c.isReady);
  
  if (!isReady) return null;

  final nativeApi = ref.read(ttsNativeApiProvider);
  return PiperAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for Supertonic adapter.
/// Checks granular download state to see if required cores are ready.
/// Uses watch to reactively update when downloads complete.
final supertonicAdapterProvider = FutureProvider<SupertonicAdapter?>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final granularState = await ref.watch(granularDownloadManagerProvider.future);
  
  // On iOS, Supertonic uses bundled CoreML models - always ready
  if (Platform.isIOS) {
    final nativeApi = ref.read(ttsNativeApiProvider);
    return SupertonicAdapter(
      nativeApi: nativeApi,
      coreDir: paths.voiceAssetsDir,
    );
  }
  
  // On Android, check if Supertonic core is ready via granular system
  final isReady = granularState.cores['supertonic_core_v1']?.isReady ?? false;
  
  if (!isReady) return null;

  final nativeApi = ref.read(ttsNativeApiProvider);
  return SupertonicAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for the routing engine with all adapters.
/// Uses watch to reactively update when adapters become available.
final ttsRoutingEngineProvider = FutureProvider<RoutingEngine>((ref) async {
  final cache = await ref.read(intelligentCacheManagerProvider.future);
  final kokoro = await ref.watch(kokoroAdapterProvider.future);
  final piper = await ref.watch(piperAdapterProvider.future);
  final supertonic = await ref.watch(supertonicAdapterProvider.future);

  return RoutingEngine(
    cache: cache,
    kokoroEngine: kokoro,
    piperEngine: piper,
    supertonicEngine: supertonic,
  );
});

/// Get the engine ID for a voice.
String? engineIdForVoice(String voiceId) {
  if (VoiceIds.isKokoro(voiceId)) return 'kokoro';
  if (VoiceIds.isPiper(voiceId)) return 'piper';
  if (VoiceIds.isSupertonic(voiceId)) return 'supertonic';
  return null;
}
