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

/// Supertonic TTS engine adapter.
///
/// Routes synthesis requests to the native Supertonic service.
/// - Android: Uses ONNX models (downloaded at runtime)
/// - iOS: Uses CoreML models (bundled with app)
///
/// Supertonic uses speaker embeddings for voice cloning.
class SupertonicAdapter implements AiVoiceEngine {
  final Logger _logger = Logger('SupertonicAdapter');

  SupertonicAdapter({
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
  
  /// Called when native notifies us a voice was unloaded.
  void onVoiceUnloaded(String voiceId) {
    _loadedVoices.remove(voiceId);
    TtsLog.info('Voice unloaded (from native): $voiceId');
  }
  
  /// Called when native sends a memory warning.
  void onMemoryWarning(int availableMB, int totalMB) {
    TtsLog.info('Memory warning: ${availableMB}MB / ${totalMB}MB');
  }

  @override
  EngineType get engineType => EngineType.supertonic;

  @override
  Future<EngineAvailability> probe() async {
    // Check native status - works for both Android and iOS
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.supertonic);
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
    // Platform-specific core paths:
    // Android: ONNX models downloaded to voice_assets
    // iOS: CoreML models downloaded to voice_assets
    final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
    final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
    
    // Path structure after extraction: {coreDir}/supertonic/{coreId}/{subdir}/
    final coreDir = Directory('${_coreDir.path}/supertonic/$coreId/$coreSubdir');

    if (await coreDir.exists()) {
      await _initEngine(coreDir.path);
      return;
    }

    throw VoiceNotAvailableException(
      'supertonic',
      'Core not installed. Please download the Supertonic core for ${Platform.isIOS ? "iOS" : "Android"}.',
    );
  }

  @override
  Future<bool> warmUp(String voiceId) async {
    // Check if this voice belongs to this engine
    if (!VoiceIds.isSupertonic(voiceId)) {
      return false;
    }

    final warmUpStartTime = DateTime.now();
    TtsLog.info('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp started for $voiceId');
    
    try {
      // Check if voice files are available
      final readiness = await checkVoiceReady(voiceId);
      if (!readiness.isReady) {
        TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp: voice not ready - ${readiness.state}');
        return false;
      }

      // Initialize engine if not already done
      if (!_coreReadiness.isReady) {
        final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
        final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
        final corePath = '${_coreDir.path}/supertonic/$coreId/$coreSubdir';
        final coreDir = Directory(corePath);
        if (await coreDir.exists()) {
          TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp: initializing engine...');
          await _initEngine(corePath);
          TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp: engine initialized');
        } else {
          TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp: core not found at $corePath');
          return false;
        }
      }

      // Load voice if not already loaded
      if (!_loadedVoices.containsKey(voiceId)) {
        final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
        final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
        final modelPath = Platform.isIOS 
            ? '${_coreDir.path}/supertonic/$coreId/$coreSubdir' 
            : '${_coreDir.path}/supertonic/$coreId/$coreSubdir/onnx/model.onnx';
        TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp: loading voice $voiceId...');
        await _loadVoice(voiceId, modelPath);
        TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp: voice loaded');
      }

      final totalDuration = DateTime.now().difference(warmUpStartTime);
      TtsLog.info('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp complete for $voiceId in ${totalDuration.inMilliseconds}ms');
      return true;
    } catch (e) {
      final totalDuration = DateTime.now().difference(warmUpStartTime);
      TtsLog.error('[SupertonicAdapter] ${DateTime.now().toIso8601String()} warmUp failed after ${totalDuration.inMilliseconds}ms: $e');
      return false;
    }
  }

  @override
  Future<CoreReadiness> getCoreReadiness(String voiceId) async {
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.supertonic);
      _coreReadiness = _mapNativeCoreStatus(status);
      return _coreReadiness;
    } catch (e) {
      _coreReadiness = CoreReadiness.failedWith('supertonic', e.toString());
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
    // Supertonic has per-voice speaker embeddings
    if (!VoiceIds.isSupertonic(voiceId)) {
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.error,
        errorMessage: 'Invalid Supertonic voice ID: $voiceId',
      );
    }

    // Check if downloaded core exists (both iOS and Android now use downloads)
    final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
    final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
    final coreDir = Directory('${_coreDir.path}/supertonic/$coreId/$coreSubdir');
    
    if (!await coreDir.exists()) {
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.coreRequired,
        nextActionUserShouldTake: 'Download Supertonic core for ${Platform.isIOS ? "iOS" : "Android"}',
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
    final segment = SegmentSynthRequest(
      segmentId: 'legacy_${request.voiceId}',
      normalizedText: request.text,
      voiceId: request.voiceId,
      outputFile: request.outFile,
      playbackRate: request.playbackRate,
      speakerId: _getSpeakerId(request.voiceId),
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

    try {
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

      // Ensure native engine is initialized
      if (!_coreReadiness.isReady) {
        // Both iOS and Android now use downloaded cores
        final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
        final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
        final corePath = '${_coreDir.path}/supertonic/$coreId/$coreSubdir';
        final coreDir = Directory(corePath);
        if (await coreDir.exists()) {
          await _initEngine(corePath);
        }
      }

      // Ensure voice is loaded in native layer
      if (!_loadedVoices.containsKey(request.voiceId)) {
        // Model path depends on platform
        final coreId = Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
        final coreSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
        final modelPath = Platform.isIOS 
            ? '${_coreDir.path}/supertonic/$coreId/$coreSubdir' 
            : '${_coreDir.path}/supertonic/$coreId/$coreSubdir/onnx/model.onnx';
        await _loadVoice(request.voiceId, modelPath);
      }

      final tmpPath = '${request.outputFile.path}.tmp';

      final nativeRequest = SynthesizeRequest(
        engineType: NativeEngineType.supertonic,
        voiceId: request.voiceId,
        text: request.normalizedText,
        outputPath: tmpPath,
        requestId: request.opId,
        speakerId: request.speakerId ?? _getSpeakerId(request.voiceId),
        speed: request.playbackRate,
      );

      final synthStartTime = DateTime.now();
      final result = await _nativeApi.synthesize(nativeRequest);
      final synthDuration = DateTime.now().difference(synthStartTime);
      
      // Debug: log synthesis result with timestamps
      _logger.info('[${DateTime.now().toIso8601String()}] Supertonic synthesis result: success=${result.success}, audioDurationMs=${result.durationMs}, synthTimeMs=${synthDuration.inMilliseconds}, sampleRate=${result.sampleRate}');

      if (request.isCancelled) {
        await _deleteTempFile(tmpPath);
        return ExtendedSynthResult.cancelled;
      }

      if (!result.success) {
        _logger.severe('[${DateTime.now().toIso8601String()}] Native synthesis failed: ${result.errorMessage} Code: ${result.errorCode}');
        await _deleteTempFile(tmpPath);
        return _handleNativeError(result, request);
      }

      // Atomic rename
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        await tmpFile.rename(request.outputFile.path);
      }

      _loadedVoices[request.voiceId] = DateTime.now();

      _logger.info('[${DateTime.now().toIso8601String()}] Supertonic synthesis complete: audioDurationMs=${result.durationMs}, synthTimeMs=${synthDuration.inMilliseconds}, textLen=${request.normalizedText.length} to ${request.outputFile.path}');
      return ExtendedSynthResult.successWith(
        outputFile: request.outputFile.path,
        durationMs: result.durationMs ?? 0,
        sampleRate: result.sampleRate ?? 24000,
      );
    } catch (e, stackTrace) {
      _logger.severe('[${DateTime.now().toIso8601String()}] Supertonic synthesis exception', e, stackTrace);
      
      if (request.canRetry && _isRecoverableError(e)) {
        _logger.info('Retrying synthesis (attempt ${request.retryAttempt + 1})');
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
      await _nativeApi.unloadVoice(NativeEngineType.supertonic, lruVoice);
      _loadedVoices.remove(lruVoice);
    }
  }

  @override
  Future<void> clearAllModels() async {
    await _nativeApi.unloadEngine(NativeEngineType.supertonic);
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

  Future<void> _initEngine(String corePath) async {
    final startTime = DateTime.now();
    TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} _initEngine starting...');
    final request = InitEngineRequest(
      engineType: NativeEngineType.supertonic,
      corePath: corePath,
    );
    await _nativeApi.initEngine(request);
    _coreReadiness = CoreReadiness.readyFor('supertonic');
    final duration = DateTime.now().difference(startTime);
    TtsLog.info('[SupertonicAdapter] ${DateTime.now().toIso8601String()} _initEngine completed in ${duration.inMilliseconds}ms');
  }

  Future<void> _loadVoice(String voiceId, String modelPath) async {
    final startTime = DateTime.now();
    TtsLog.debug('[SupertonicAdapter] ${DateTime.now().toIso8601String()} _loadVoice starting for $voiceId...');
    final request = LoadVoiceRequest(
      engineType: NativeEngineType.supertonic,
      voiceId: voiceId,
      modelPath: modelPath,
      speakerId: _getSpeakerId(voiceId),
    );
    await _nativeApi.loadVoice(request);
    final duration = DateTime.now().difference(startTime);
    TtsLog.info('[SupertonicAdapter] ${DateTime.now().toIso8601String()} _loadVoice completed for $voiceId in ${duration.inMilliseconds}ms');
  }

  int _getSpeakerId(String voiceId) {
    // Supertonic voice IDs: supertonic_m1, supertonic_f1, etc.
    // Map to speaker index
    final suffix = voiceId.replaceFirst('supertonic_', '');
    final isMale = suffix.startsWith('m');
    final num = int.tryParse(suffix.substring(1)) ?? 1;
    
    // Male voices: 0-4, Female voices: 5-9
    return isMale ? (num - 1) : (5 + num - 1);
  }

  CoreReadiness _mapNativeCoreStatus(CoreStatus status) {
    return CoreReadiness(
      state: _mapNativeState(status.state),
      engineId: 'supertonic',
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
      NativeErrorCode.outOfMemory => EngineError.outOfMemory,
      NativeErrorCode.inferenceFailed => EngineError.inferenceFailed,
      NativeErrorCode.cancelled => EngineError.cancelled,
      NativeErrorCode.runtimeCrash => EngineError.runtimeCrash,
      NativeErrorCode.invalidInput => EngineError.invalidInput,
      NativeErrorCode.fileWriteError => EngineError.fileWriteError,
      NativeErrorCode.busy => EngineError.busy,
      NativeErrorCode.timeout => EngineError.timeout,
      NativeErrorCode.unknown => EngineError.unknown,
    };
  }

  EngineError _mapExceptionToError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('service_dead') || msg.contains('binder')) {
      return EngineError.runtimeCrash;
    }
    if (msg.contains('memory') || msg.contains('oom')) {
      return EngineError.outOfMemory;
    }
    if (msg.contains('timeout')) {
      return EngineError.timeout;
    }
    return EngineError.unknown;
  }

  bool _isRecoverableError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('service_dead') ||
        msg.contains('binder') ||
        msg.contains('timeout') ||
        msg.contains('busy');
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
