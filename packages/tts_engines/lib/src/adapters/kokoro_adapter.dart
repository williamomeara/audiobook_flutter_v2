import 'dart:async';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:platform_android_tts/generated/tts_api.g.dart';

import '../interfaces/ai_voice_engine.dart';
import '../interfaces/segment_synth_request.dart';
import '../interfaces/synth_request.dart';
import '../interfaces/synth_result.dart';
import '../interfaces/tts_state_machines.dart';

/// Kokoro TTS engine adapter.
///
/// Routes synthesis requests to the native Kokoro ONNX service
/// via Pigeon-generated bindings.
class KokoroAdapter implements AiVoiceEngine {
  KokoroAdapter({
    required TtsNativeApi nativeApi,
    required Directory coreDir,
  })  : _nativeApi = nativeApi,
        _coreDir = coreDir;

  final TtsNativeApi _nativeApi;
  final Directory _coreDir;

  /// Track loaded voices for LRU management.
  final Map<String, DateTime> _loadedVoices = {};

  /// Stream controllers for readiness updates.
  final Map<String, StreamController<CoreReadiness>> _readinessControllers = {};

  /// Active synthesis requests for cancellation.
  final Map<String, SegmentSynthRequest> _activeRequests = {};

  /// Current core state.
  CoreReadiness _coreReadiness = CoreReadiness.notStarted;

  @override
  EngineType get engineType => EngineType.kokoro;

  @override
  Future<EngineAvailability> probe() async {
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.kokoro);
      if (status.state == NativeCoreState.ready) {
        return EngineAvailability.available;
      }
      if (status.state == NativeCoreState.notStarted) {
        final coreExists = await _getCoreDir().exists();
        return coreExists
            ? EngineAvailability.available
            : EngineAvailability.needsCore;
      }
      return EngineAvailability.needsCore;
    } catch (e) {
      return EngineAvailability.error;
    }
  }

  @override
  Future<void> ensureCoreReady(CoreSelector selector) async {
    final coreId = _coreIdFor(selector);
    final coreDir = Directory('${_coreDir.path}/$coreId');

    if (await coreDir.exists()) {
      await _initEngine(coreDir.path);
      return;
    }

    // Core needs download - this should be triggered by asset manager
    throw VoiceNotAvailableException(
      'kokoro',
      'Core not installed. Please download the Kokoro ${selector.variant} core.',
    );
  }

  @override
  Future<CoreReadiness> getCoreReadiness(String voiceId) async {
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.kokoro);
      _coreReadiness = _mapNativeCoreStatus(status);
      return _coreReadiness;
    } catch (e) {
      _coreReadiness = CoreReadiness.failedWith('kokoro', e.toString());
      return _coreReadiness;
    }
  }

  @override
  Stream<CoreReadiness> watchCoreReadiness(String coreId) {
    _readinessControllers[coreId] ??=
        StreamController<CoreReadiness>.broadcast();
    return _readinessControllers[coreId]!.stream;
  }

  @override
  Future<VoiceReadiness> checkVoiceReady(String voiceId) async {
    // Kokoro voices share the core model
    final coreReady = await getCoreReadiness(voiceId);

    if (coreReady.isFailed) {
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.error,
        coreState: coreReady.state,
        errorMessage: coreReady.errorMessage,
      );
    }

    if (!coreReady.isReady) {
      if (coreReady.state == CoreReadyState.notStarted) {
        return VoiceReadiness(
          voiceId: voiceId,
          state: VoiceReadyState.coreRequired,
          coreState: coreReady.state,
          nextActionUserShouldTake: 'Download Kokoro core (250MB)',
        );
      }
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.coreLoading,
        coreState: coreReady.state,
      );
    }

    return VoiceReadiness(
      voiceId: voiceId,
      state: VoiceReadyState.voiceReady,
      coreState: coreReady.state,
    );
  }

  @override
  Future<SynthResult> synthesizeToFile(SynthRequest request) async {
    final segment = SegmentSynthRequest(
      segmentId: 'legacy_${request.voiceId}',
      normalizedText: request.text,
      voiceId: request.voiceId,
      outputFile: request.outFile,
      playbackRate: request.playbackRate,
      speakerId: VoiceIds.kokoroSpeakerId(request.voiceId),
    );

    final result = await synthesizeSegment(segment);

    if (!result.success) {
      throw SynthesisException(
        result.errorMessage ?? 'Synthesis failed',
        voiceId: request.voiceId,
      );
    }

    return SynthResult(
      file: request.outFile,
      durationMs: result.durationMs ?? 0,
      sampleRate: result.sampleRate,
    );
  }

  @override
  Future<ExtendedSynthResult> synthesizeSegment(
      SegmentSynthRequest request) async {
    // Track for cancellation
    _activeRequests[request.opId] = request;

    try {
      // Check voice ready
      final readiness = await checkVoiceReady(request.voiceId);
      if (!readiness.isReady) {
        return ExtendedSynthResult.failedWith(
          code: EngineError.modelMissing,
          message: readiness.nextActionUserShouldTake ??
              'Voice not ready: ${readiness.state}',
          stage: SynthStage.voiceReady,
        );
      }

      if (request.isCancelled) {
        return ExtendedSynthResult.cancelled;
      }

      // Write to temp file first (atomic pattern)
      final tmpPath = '${request.outputFile.path}.tmp';

      final nativeRequest = SynthesizeRequest(
        engineType: NativeEngineType.kokoro,
        voiceId: request.voiceId,
        text: request.normalizedText,
        outputPath: tmpPath,
        requestId: request.opId,
        speakerId: request.speakerId ?? VoiceIds.kokoroSpeakerId(request.voiceId),
        speed: request.playbackRate,
      );

      final result = await _nativeApi.synthesize(nativeRequest);

      if (request.isCancelled) {
        // Clean up temp file
        await _deleteTempFile(tmpPath);
        return ExtendedSynthResult.cancelled;
      }

      if (!result.success) {
        await _deleteTempFile(tmpPath);
        return _handleNativeError(result, request);
      }

      // Atomic rename: tmp -> final
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        await tmpFile.rename(request.outputFile.path);
      }

      // Update LRU tracking
      _loadedVoices[request.voiceId] = DateTime.now();

      return ExtendedSynthResult.successWith(
        outputFile: request.outputFile.path,
        durationMs: result.durationMs ?? 0,
        sampleRate: result.sampleRate ?? 24000,
      );
    } catch (e) {
      // Handle retry for recoverable errors
      if (request.canRetry && _isRecoverableError(e)) {
        request.incrementRetry();
        return synthesizeSegment(request);
      }

      return ExtendedSynthResult.failedWith(
        code: _mapExceptionToError(e),
        message: e.toString(),
        stage: SynthStage.failed,
        retryCount: request.retryAttempt,
      );
    } finally {
      _activeRequests.remove(request.opId);
    }
  }

  @override
  Future<void> cancelSynth(String requestId) async {
    final request = _activeRequests[requestId];
    if (request != null) {
      request.cancel();
      try {
        await _nativeApi.cancelSynthesis(requestId);
        // Clean up temp file
        await _deleteTempFile('${request.outputFile.path}.tmp');
      } catch (_) {
        // Best effort cancellation
      }
    }
  }

  @override
  Future<bool> isVoiceReady(String voiceId) async {
    final readiness = await checkVoiceReady(voiceId);
    return readiness.isReady;
  }

  @override
  Future<int> getLoadedModelCount() async {
    final memInfo = await _nativeApi.getMemoryInfo();
    return memInfo.loadedModelCount;
  }

  @override
  Future<void> unloadLeastUsedModel() async {
    if (_loadedVoices.isEmpty) return;

    // Find least recently used voice
    String? lruVoice;
    DateTime? lruTime;
    for (final entry in _loadedVoices.entries) {
      if (lruTime == null || entry.value.isBefore(lruTime)) {
        lruVoice = entry.key;
        lruTime = entry.value;
      }
    }

    if (lruVoice != null) {
      await _nativeApi.unloadVoice(NativeEngineType.kokoro, lruVoice);
      _loadedVoices.remove(lruVoice);
    }
  }

  @override
  Future<void> clearAllModels() async {
    await _nativeApi.unloadEngine(NativeEngineType.kokoro);
    _loadedVoices.clear();
    _coreReadiness = CoreReadiness.notStarted;
  }

  @override
  Future<void> dispose() async {
    await clearAllModels();

    for (final controller in _readinessControllers.values) {
      await controller.close();
    }
    _readinessControllers.clear();
    _activeRequests.clear();
  }

  // Private helpers

  Directory _getCoreDir() {
    return Directory('${_coreDir.path}/kokoro_int8_v1');
  }

  String _coreIdFor(CoreSelector selector) {
    return selector.preferInt8 ? 'kokoro_int8_v1' : 'kokoro_fp32_v1';
  }

  Future<void> _initEngine(String corePath) async {
    final request = InitEngineRequest(
      engineType: NativeEngineType.kokoro,
      corePath: corePath,
    );
    await _nativeApi.initEngine(request);
    _coreReadiness = CoreReadiness.readyFor('kokoro');
    _notifyReadinessChange('kokoro', _coreReadiness);
  }

  void _notifyReadinessChange(String coreId, CoreReadiness readiness) {
    _readinessControllers[coreId]?.add(readiness);
  }

  CoreReadiness _mapNativeCoreStatus(CoreStatus status) {
    return CoreReadiness(
      state: _mapNativeState(status.state),
      engineId: 'kokoro',
      errorMessage: status.errorMessage,
      downloadProgress: status.downloadProgress,
    );
  }

  CoreReadyState _mapNativeState(NativeCoreState state) {
    return switch (state) {
      NativeCoreState.notStarted => CoreReadyState.notStarted,
      NativeCoreState.downloading => CoreReadyState.downloading,
      NativeCoreState.extracting => CoreReadyState.extracting,
      NativeCoreState.verifying => CoreReadyState.verifying,
      NativeCoreState.loaded => CoreReadyState.loaded,
      NativeCoreState.ready => CoreReadyState.ready,
      NativeCoreState.failed => CoreReadyState.failed,
    };
  }

  ExtendedSynthResult _handleNativeError(
      SynthesizeResult result, SegmentSynthRequest request) {
    final code = result.errorCode ?? NativeErrorCode.unknown;
    final engineError = _mapNativeError(code);

    // Handle OOM with retry after unload
    if (engineError == EngineError.inferenceFailed &&
        code == NativeErrorCode.outOfMemory) {
      if (request.canRetry) {
        // Schedule unload and retry
        unawaited(_unloadAndRetry(request));
        return ExtendedSynthResult.failedWith(
          code: engineError,
          message: 'Out of memory, retrying after model unload...',
          stage: SynthStage.inferencing,
        );
      }
    }

    return ExtendedSynthResult.failedWith(
      code: engineError,
      message: result.errorMessage ?? 'Native synthesis failed',
      stage: SynthStage.inferencing,
      retryCount: request.retryAttempt,
    );
  }

  Future<void> _unloadAndRetry(SegmentSynthRequest request) async {
    await unloadLeastUsedModel();
    await Future.delayed(const Duration(milliseconds: 100));
    request.incrementRetry();
    await synthesizeSegment(request);
  }

  EngineError _mapNativeError(NativeErrorCode code) {
    return switch (code) {
      NativeErrorCode.none => EngineError.unknown,
      NativeErrorCode.modelMissing => EngineError.modelMissing,
      NativeErrorCode.modelCorrupted => EngineError.modelCorrupted,
      NativeErrorCode.outOfMemory => EngineError.inferenceFailed,
      NativeErrorCode.inferenceFailed => EngineError.inferenceFailed,
      NativeErrorCode.cancelled => EngineError.cancelled,
      NativeErrorCode.runtimeCrash => EngineError.runtimeCrash,
      NativeErrorCode.invalidInput => EngineError.invalidInput,
      NativeErrorCode.fileWriteError => EngineError.fileWriteError,
      NativeErrorCode.unknown => EngineError.unknown,
    };
  }

  EngineError _mapExceptionToError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('service_dead') || msg.contains('binder')) {
      return EngineError.runtimeCrash;
    }
    if (msg.contains('memory')) {
      return EngineError.inferenceFailed;
    }
    return EngineError.unknown;
  }

  bool _isRecoverableError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('service_dead') ||
        msg.contains('binder') ||
        msg.contains('timeout');
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort cleanup
    }
  }
}

// Silence unawaited future warning
void unawaited(Future<void>? future) {}
