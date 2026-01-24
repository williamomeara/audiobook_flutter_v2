import 'dart:async';
import 'package:logging/logging.dart';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:platform_android_tts/generated/tts_api.g.dart';

import '../interfaces/ai_voice_engine.dart';
import '../interfaces/segment_synth_request.dart';
import '../interfaces/synth_request.dart';
import '../interfaces/synth_result.dart';
import '../interfaces/tts_state_machines.dart';
import '../tts_log.dart';

/// Piper TTS engine adapter.
///
/// Routes synthesis requests to the native Piper ONNX service.
/// Piper requires phonemizer toolchain for text-to-phoneme conversion.
class PiperAdapter implements AiVoiceEngine {
  final Logger _logger = Logger('PiperAdapter');

  PiperAdapter({
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
  EngineType get engineType => EngineType.piper;

  @override
  Future<EngineAvailability> probe() async {
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.piper);
      if (status.state == NativeCoreState.ready) {
        return EngineAvailability.available;
      }
      return EngineAvailability.needsCore;
    } catch (e) {
      return EngineAvailability.error;
    }
  }

  @override
  Future<void> ensureCoreReady(CoreSelector selector) async {
    // Piper is self-contained per voice in this implementation.
    await _initEngine(_coreDir.path);
  }

  @override
  Future<CoreReadiness> getCoreReadiness(String voiceId) async {
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.piper);
      _coreReadiness = _mapNativeCoreStatus(status);
      return _coreReadiness;
    } catch (e) {
      _coreReadiness = CoreReadiness.failedWith('piper', e.toString());
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
    // For Piper, each voice has its own model file
    final modelKey = VoiceIds.piperModelKey(voiceId);
    if (modelKey == null) {
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.error,
        errorMessage: 'Invalid Piper voice ID: $voiceId',
      );
    }

    // Check if voice model exists - new path structure: piper/{coreId}/
    final coreId = _getCoreIdForModelKey(modelKey);
    final voiceDir = Directory('${_coreDir.path}/piper/$coreId');
    if (!await voiceDir.exists()) {
      _logger.warning('Piper voice model missing for $voiceId: $modelKey');
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.coreRequired,
        nextActionUserShouldTake: 'Download Piper voice model',
      );
    }

    final coreReady = await getCoreReadiness(voiceId);
    if (!coreReady.isReady && coreReady.state != CoreReadyState.notStarted) {
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
    TtsLog.info('synthesizeToFile called for voice: ${request.voiceId}');
    
    final segment = SegmentSynthRequest(
      segmentId: 'legacy_${request.voiceId}',
      normalizedText: request.text,
      voiceId: request.voiceId,
      outputFile: request.outFile,
      playbackRate: request.playbackRate,
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
    _activeRequests[request.opId] = request;
    TtsLog.info('synthesizeSegment: ${request.voiceId}');

    // Retry loop instead of recursion to prevent stack overflow
    while (true) {
      try {
        TtsLog.debug('Checking voice readiness...');
        final readiness = await checkVoiceReady(request.voiceId);
        TtsLog.debug('Voice readiness: ${readiness.state} - isReady: ${readiness.isReady}');
        
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

        // Piper-specific: need to load the voice model if not loaded
        final modelKey = VoiceIds.piperModelKey(request.voiceId);
        TtsLog.debug('modelKey: $modelKey, loaded voices: ${_loadedVoices.keys.toList()}');
        
        if (modelKey != null && !_loadedVoices.containsKey(request.voiceId)) {
          final coreId = _getCoreIdForModelKey(modelKey);
          final modelPath = '${_coreDir.path}/piper/$coreId';
          TtsLog.info('Loading voice from: $modelPath');
          await _loadVoice(request.voiceId, modelPath);
          TtsLog.info('Voice loaded successfully');
        }

        final tmpPath = '${request.outputFile.path}.tmp';

        TtsLog.debug('Calling native synthesize...');
        final nativeRequest = SynthesizeRequest(
          engineType: NativeEngineType.piper,
          voiceId: request.voiceId,
          text: request.normalizedText,
          outputPath: tmpPath,
          requestId: request.opId,
          speed: request.playbackRate,
        );

        final result = await _nativeApi.synthesize(nativeRequest);
        TtsLog.debug('Native synthesize returned: success=${result.success}, error=${result.errorMessage}');

        if (request.isCancelled) {
          await _deleteTempFile(tmpPath);
          return ExtendedSynthResult.cancelled;
        }

        if (!result.success) {
          _logger.severe('Native Piper synthesis failed: ${result.errorMessage} Code: ${result.errorCode}');
          await _deleteTempFile(tmpPath);
          return _handleNativeError(result, request);
        }

        // Atomic rename
        final tmpFile = File(tmpPath);
        if (await tmpFile.exists()) {
          await tmpFile.rename(request.outputFile.path);
        }

        _loadedVoices[request.voiceId] = DateTime.now();

        return ExtendedSynthResult.successWith(
          outputFile: request.outputFile.path,
          durationMs: result.durationMs ?? 0,
          sampleRate: result.sampleRate ?? 22050, // Piper typically uses 22050
        );
      } catch (e, stackTrace) {
        _logger.severe('Piper synthesis exception', e, stackTrace);
        
        if (request.canRetry && _isRecoverableError(e)) {
          _logger.info('Retrying synthesis (attempt ${request.retryAttempt + 1})');
          request.incrementRetry();
          // Loop continues to retry
          continue;
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
  }

  @override
  Future<void> cancelSynth(String requestId) async {
    final request = _activeRequests[requestId];
    if (request != null) {
      request.cancel();
      try {
        await _nativeApi.cancelSynthesis(requestId);
        await _deleteTempFile('${request.outputFile.path}.tmp');
      } catch (_) {}
    }
  }

  @override
  Future<bool> isVoiceReady(String voiceId) async {
    final readiness = await checkVoiceReady(voiceId);
    return readiness.isReady;
  }

  @override
  Future<int> getLoadedModelCount() async {
    return _loadedVoices.length;
  }

  @override
  Future<void> unloadLeastUsedModel() async {
    if (_loadedVoices.isEmpty) return;

    String? lruVoice;
    DateTime? lruTime;
    for (final entry in _loadedVoices.entries) {
      if (lruTime == null || entry.value.isBefore(lruTime)) {
        lruVoice = entry.key;
        lruTime = entry.value;
      }
    }

    if (lruVoice != null) {
      await _nativeApi.unloadVoice(NativeEngineType.piper, lruVoice);
      _loadedVoices.remove(lruVoice);
    }
  }

  @override
  Future<void> clearAllModels() async {
    await _nativeApi.unloadEngine(NativeEngineType.piper);
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

  /// Map modelKey to coreId for new path structure
  String _getCoreIdForModelKey(String modelKey) {
    // Map model keys to core IDs based on manifest
    switch (modelKey) {
      case 'en_GB-alan-medium':
        return 'piper_alan_gb_v1';
      case 'en_US-lessac-medium':
        return 'piper_lessac_us_v1';
      default:
        // Fall back to model key for unknown models
        return modelKey;
    }
  }

  Future<void> _initEngine(String corePath) async {
    final request = InitEngineRequest(
      engineType: NativeEngineType.piper,
      corePath: corePath,
    );
    await _nativeApi.initEngine(request);
    _coreReadiness = CoreReadiness.readyFor('piper');
  }

  Future<void> _loadVoice(String voiceId, String modelPath) async {
    final request = LoadVoiceRequest(
      engineType: NativeEngineType.piper,
      voiceId: voiceId,
      modelPath: modelPath,
    );
    await _nativeApi.loadVoice(request);
    _loadedVoices[voiceId] = DateTime.now();
  }

  CoreReadiness _mapNativeCoreStatus(CoreStatus status) {
    return CoreReadiness(
      state: _mapNativeState(status.state),
      engineId: 'piper',
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
    return ExtendedSynthResult.failedWith(
      code: _mapNativeError(code),
      message: result.errorMessage ?? 'Native synthesis failed',
      stage: SynthStage.inferencing,
      retryCount: request.retryAttempt,
    );
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
    } catch (_) {}
  }
}
