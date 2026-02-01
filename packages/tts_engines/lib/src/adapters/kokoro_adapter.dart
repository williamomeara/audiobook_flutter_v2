import 'dart:async';
import 'package:logging/logging.dart';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:platform_android_tts/generated/tts_api.g.dart';

import '../interfaces/ai_voice_engine.dart';
import '../interfaces/segment_synth_request.dart';
import '../interfaces/synth_request.dart';
import '../interfaces/synth_result.dart';
import '../interfaces/tts_state_machines.dart';
import '../tts_log.dart';

/// Kokoro TTS engine adapter.
///
/// Routes synthesis requests to the native Kokoro ONNX service
/// via Pigeon-generated bindings.
class KokoroAdapter implements AiVoiceEngine {
  final Logger _logger = Logger('KokoroAdapter');

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
  
  /// Completer to serialize _initEngine calls.
  /// This prevents multiple concurrent calls to initEngine, which would
  /// both wait for the slow model loading.
  Completer<void>? _initEngineCompleter;
  
  /// Called when native notifies us a voice was unloaded.
  void onVoiceUnloaded(String voiceId) {
    _loadedVoices.remove(voiceId);
    TtsLog.info('Voice unloaded (from native): $voiceId');
  }
  
  /// Called when native sends a memory warning.
  void onMemoryWarning(int availableMB, int totalMB) {
    TtsLog.info('Memory warning: ${availableMB}MB / ${totalMB}MB');
    // Could trigger proactive unloading here
  }

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
  Future<bool> warmUp(String voiceId) async {
    // Check if this voice belongs to this engine
    if (!VoiceIds.isKokoro(voiceId)) {
      return false;
    }

    final warmUpStartTime = DateTime.now();
    TtsLog.info('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp started for $voiceId');

    try {
      // Check if voice files are available
      final readiness = await checkVoiceReady(voiceId);
      if (!readiness.isReady) {
        TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp: voice not ready');
        return false;
      }

      // Initialize engine if needed
      if (!_coreReadiness.isReady) {
        final coreDir = _getCoreDir();
        if (await coreDir.exists()) {
          TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp: initializing engine...');
          await _initEngine(coreDir.path);
          TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp: engine initialized');
        } else {
          TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp: core not found');
          return false;
        }
      }

      // Load voice if not already loaded
      // Kokoro voices are bundled with core - use core path with speaker ID
      if (!_loadedVoices.containsKey(voiceId)) {
        final modelPath = _getCoreDir().path;
        TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp: loading voice $voiceId...');
        await _loadVoice(voiceId, modelPath, 
          speakerId: VoiceIds.kokoroSpeakerId(voiceId));
        TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp: voice loaded');
      }

      final totalDuration = DateTime.now().difference(warmUpStartTime);
      TtsLog.info('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp complete for $voiceId in ${totalDuration.inMilliseconds}ms');
      return true;
    } catch (e) {
      final totalDuration = DateTime.now().difference(warmUpStartTime);
      TtsLog.error('[KokoroAdapter] ${DateTime.now().toIso8601String()} warmUp failed after ${totalDuration.inMilliseconds}ms: $e');
      return false;
    }
  }

  @override
  Future<CoreReadiness> getCoreReadiness(String voiceId) async {
    try {
      final status = await _nativeApi.getCoreStatus(NativeEngineType.kokoro);
      
      // If native reports notStarted, check if core files exist and auto-init
      if (status.state == NativeCoreState.notStarted) {
        final coreDir = _getCoreDir();
        if (await coreDir.exists()) {
          // Core is downloaded but not initialized - init now
          developer.log('[KokoroAdapter] Auto-initializing engine from ${coreDir.path}');
          await _initEngine(coreDir.path);
          _coreReadiness = CoreReadiness.readyFor('kokoro');
          return _coreReadiness;
        }
      }
      
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

    // Retry loop instead of recursion to prevent stack overflow
    while (true) {
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

        // Kokoro: load the voice model if not loaded
        if (!_loadedVoices.containsKey(request.voiceId)) {
          final modelPath = _getCoreDir().path;
          TtsLog.info('Loading Kokoro voice from: $modelPath');
          await _loadVoice(request.voiceId, modelPath, 
            speakerId: VoiceIds.kokoroSpeakerId(request.voiceId));
          TtsLog.info('Kokoro voice loaded: ${request.voiceId}');
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
          _logger.severe('Native Kokoro synthesis failed: ${result.errorMessage} Code: ${result.errorCode}');
          await _deleteTempFile(tmpPath);
          
          // Handle OOM with proper retry (not fire-and-forget)
          final code = result.errorCode ?? NativeErrorCode.unknown;
          if (code == NativeErrorCode.outOfMemory && request.canRetry) {
            TtsLog.info('OOM detected, unloading models and retrying...');
            await unloadLeastUsedModel();
            await Future.delayed(const Duration(milliseconds: 200));
            request.incrementRetry();
            continue; // Retry in loop
          }
          
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
          continue; // Retry in loop
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
    // Platform-specific core paths after Phase 1 migration
    final coreId = Platform.isIOS ? 'kokoro_core_ios_v1' : 'kokoro_core_android_v1';
    return Directory('${_coreDir.path}/kokoro/$coreId');
  }

  String _coreIdFor(CoreSelector selector) {
    // Platform-specific core IDs
    return Platform.isIOS ? 'kokoro_core_ios_v1' : 'kokoro_core_android_v1';
  }

  /// Initialize the native engine.
  /// 
  /// Uses a Completer to serialize calls - if another call is already in
  /// progress, this waits for it instead of starting a second init.
  Future<void> _initEngine(String corePath) async {
    // If already ready, skip
    if (_coreReadiness.isReady) {
      TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} _initEngine: already ready, skipping');
      return;
    }
    
    // If another init is in progress, wait for it
    if (_initEngineCompleter != null) {
      TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} _initEngine: waiting for existing init...');
      await _initEngineCompleter!.future;
      TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} _initEngine: existing init completed');
      return;
    }
    
    // Start new init
    _initEngineCompleter = Completer<void>();
    final startTime = DateTime.now();
    TtsLog.debug('[KokoroAdapter] ${DateTime.now().toIso8601String()} _initEngine starting...');
    
    try {
      final request = InitEngineRequest(
        engineType: NativeEngineType.kokoro,
        corePath: corePath,
      );
      await _nativeApi.initEngine(request);
      _coreReadiness = CoreReadiness.readyFor('kokoro');
      _notifyReadinessChange('kokoro', _coreReadiness);
      final duration = DateTime.now().difference(startTime);
      TtsLog.info('[KokoroAdapter] ${DateTime.now().toIso8601String()} _initEngine completed in ${duration.inMilliseconds}ms');
      _initEngineCompleter!.complete();
    } catch (e) {
      TtsLog.error('[KokoroAdapter] ${DateTime.now().toIso8601String()} _initEngine failed: $e');
      _initEngineCompleter!.completeError(e);
      rethrow;
    } finally {
      _initEngineCompleter = null;
    }
  }
  
  Future<void> _loadVoice(String voiceId, String modelPath, {int? speakerId}) async {
    final request = LoadVoiceRequest(
      engineType: NativeEngineType.kokoro,
      voiceId: voiceId,
      modelPath: modelPath,
      speakerId: speakerId,
    );
    await _nativeApi.loadVoice(request);
    _loadedVoices[voiceId] = DateTime.now();
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

    // OOM is now handled in the main synthesis loop
    return ExtendedSynthResult.failedWith(
      code: engineError,
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
    } catch (_) {
      // Best effort cleanup
    }
  }
}

// Silence unawaited future warning
void unawaited(Future<void>? future) {}
