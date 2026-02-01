import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../interfaces/ai_voice_engine.dart';
import '../interfaces/engine_memory_manager.dart';
import '../interfaces/segment_synth_request.dart';
import '../interfaces/synth_request.dart';
import '../interfaces/synth_result.dart';
import '../interfaces/tts_state_machines.dart';
import '../cache/audio_cache.dart';
import '../tts_log.dart';

/// Routes synthesis requests to the appropriate voice engine.
///
/// This is the main entry point for synthesis. It:
/// 1. Checks the cache for existing audio
/// 2. Routes to the correct engine based on voice ID
/// 3. Caches the result for future use
/// 4. Manages engine memory using the Active Engine Pattern
class RoutingEngine implements AiVoiceEngine {
  RoutingEngine({
    required this.cache,
    this.piperEngine,
    this.supertonicEngine,
    this.kokoroEngine,
    EngineMemoryManager? memoryManager,
    this.onSynthesisComplete,
  }) : _memoryManager = memoryManager ?? EngineMemoryManager();

  /// Audio cache for storing synthesized files.
  final AudioCache cache;

  /// Piper TTS engine adapter.
  final AiVoiceEngine? piperEngine;

  /// Supertonic TTS engine adapter.
  final AiVoiceEngine? supertonicEngine;

  /// Kokoro TTS engine adapter.
  final AiVoiceEngine? kokoroEngine;
  
  /// Memory manager for engine lifecycle.
  final EngineMemoryManager _memoryManager;

  /// Track active requests for cancellation.
  final Map<String, String> _activeRequests = {};
  
  /// Lock to serialize _prepareEngineForVoice calls to prevent concurrent model loading.
  /// Concurrent loading can double memory usage causing OOM crashes on iOS.
  Completer<void>? _prepareLock;
  
  /// Cached stream controllers for core readiness (prevents memory leak).
  final Map<String, StreamController<CoreReadiness>> _readinessControllers = {};
  
  /// Stream subscriptions for core readiness aggregation.
  final Map<String, List<StreamSubscription<CoreReadiness>>> _readinessSubscriptions = {};

  /// Callback invoked after successful synthesis, before returning result.
  /// Can be used for post-processing like compression.
  /// Receives the output file path.
  final Future<void> Function(String filePath)? onSynthesisComplete;

  @override
  EngineType get engineType => EngineType.device; // Router has no specific type

  @override
  Future<EngineAvailability> probe() async {
    // Router is always available; individual engines may not be
    return EngineAvailability.available;
  }

  @override
  Future<void> ensureCoreReady(CoreSelector selector) async {
    // Delegate to all engines that might be used
    await Future.wait([
      if (piperEngine != null)
        piperEngine!.ensureCoreReady(CoreSelector.defaultPiper),
      if (supertonicEngine != null)
        supertonicEngine!.ensureCoreReady(CoreSelector.defaultSupertonic),
      if (kokoroEngine != null) kokoroEngine!.ensureCoreReady(selector),
    ]);
  }

  @override
  Future<bool> warmUp(String voiceId) async {
    final startTime = DateTime.now();
    debugPrint('[RoutingEngine] ${startTime.toIso8601String()} warmUp($voiceId) started');
    
    // Prepare engine (unloads others if needed for memory)
    // This should happen during warmUp, not during synthesis, to avoid
    // race conditions where the old engine is unloaded while still in use.
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} warmUp: calling _prepareEngineForVoice...');
    final engine = await _prepareEngineForVoice(voiceId);
    final prepareTime = DateTime.now().difference(startTime);
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} warmUp: _prepareEngineForVoice completed in ${prepareTime.inMilliseconds}ms');
    
    if (engine == null) {
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} warmUp: no engine for voice, returning false');
      return false;
    }
    
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} warmUp: calling engine.warmUp...');
    final warmUpStart = DateTime.now();
    final result = await engine.warmUp(voiceId);
    final warmUpTime = DateTime.now().difference(warmUpStart);
    final totalTime = DateTime.now().difference(startTime);
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} warmUp: engine.warmUp completed in ${warmUpTime.inMilliseconds}ms (total: ${totalTime.inMilliseconds}ms)');
    
    return result;
  }

  @override
  Future<CoreReadiness> getCoreReadiness(String voiceId) async {
    final engine = _engineForVoice(voiceId);
    if (engine == null) {
      return CoreReadiness.failedWith('unknown', 'No engine for voice $voiceId');
    }
    return engine.getCoreReadiness(voiceId);
  }

  @override
  Stream<CoreReadiness> watchCoreReadiness(String coreId) {
    // Return existing controller if already created
    if (_readinessControllers.containsKey(coreId)) {
      return _readinessControllers[coreId]!.stream;
    }
    
    // Track listener count for proper cleanup
    var listenerCount = 0;
    
    // Create new controller with proper lifecycle management
    final controller = StreamController<CoreReadiness>.broadcast(
      onListen: () {
        listenerCount++;
      },
      onCancel: () {
        listenerCount--;
        // Cleanup when all listeners are gone
        if (listenerCount <= 0) {
          _cleanupReadinessSubscriptions(coreId);
        }
      },
    );
    _readinessControllers[coreId] = controller;
    _readinessSubscriptions[coreId] = [];
    
    void addFromEngine(AiVoiceEngine? engine) {
      if (engine != null) {
        final subscription = engine.watchCoreReadiness(coreId).listen(
          controller.add,
          onError: controller.addError,
        );
        _readinessSubscriptions[coreId]!.add(subscription);
      }
    }
    
    addFromEngine(kokoroEngine);
    addFromEngine(piperEngine);
    addFromEngine(supertonicEngine);
    
    return controller.stream;
  }
  
  /// Cleanup subscriptions for a core ID.
  void _cleanupReadinessSubscriptions(String coreId) {
    final subscriptions = _readinessSubscriptions.remove(coreId);
    if (subscriptions != null) {
      for (final sub in subscriptions) {
        sub.cancel();
      }
    }
    final controller = _readinessControllers.remove(coreId);
    controller?.close();
  }

  @override
  Future<VoiceReadiness> checkVoiceReady(String voiceId) async {
    final engine = _engineForVoice(voiceId);
    if (engine == null) {
      return VoiceReadiness(
        voiceId: voiceId,
        state: VoiceReadyState.error,
        errorMessage: 'No engine available for voice $voiceId',
      );
    }
    return engine.checkVoiceReady(voiceId);
  }

  @override
  Future<SynthResult> synthesizeToFile(SynthRequest request) async {
    final voiceId = request.voiceId;
    
    // Debug: log what voice is being requested
    TtsLog.info('synthesizeToFile called for voice: $voiceId');
    TtsLog.debug('Engines available - Kokoro: ${kokoroEngine != null}, Piper: ${piperEngine != null}, Supertonic: ${supertonicEngine != null}');

    // Check cache first
    final cacheKey = CacheKeyGenerator.generate(
      voiceId: voiceId,
      text: request.text,
      playbackRate: request.playbackRate,
    );

    if (await cache.isReady(cacheKey)) {
      final file = await cache.fileFor(cacheKey);
      await cache.markUsed(cacheKey);
      // Return cached file with estimated duration
      final durationMs = estimateDurationMs(request.text);
      TtsLog.info('Returning cached audio for $voiceId');
      return SynthResult(file: file, durationMs: durationMs);
    }

    // Prepare engine (unloads others if needed for memory)
    final engine = await _prepareEngineForVoice(voiceId);
    TtsLog.debug('Engine for $voiceId: $engine');
    if (engine == null) {
      throw VoiceNotAvailableException(
        voiceId,
        'No engine available for voice "$voiceId". '
        'Please select a different voice.',
      );
    }

    // Create output file in cache
    final outFile = await cache.fileFor(cacheKey);
    final modifiedRequest = SynthRequest(
      voiceId: request.voiceId,
      text: request.text,
      playbackRate: request.playbackRate,
      outFile: outFile,
      tuning: request.tuning,
    );

    // Synthesize
    final result = await engine.synthesizeToFile(modifiedRequest);

    // Post-synthesis callback (e.g., compression)
    if (onSynthesisComplete != null) {
      await onSynthesisComplete!(result.file.path);
    }

    // Mark as used
    await cache.markUsed(cacheKey);

    return result;
  }

  @override
  Future<ExtendedSynthResult> synthesizeSegment(
      SegmentSynthRequest request) async {
    final voiceId = request.voiceId;
    
    // Track request for cancellation
    _activeRequests[request.opId] = voiceId;

    try {
      // Check cache first
      final cacheKey = CacheKeyGenerator.generate(
        voiceId: voiceId,
        text: request.normalizedText,
        playbackRate: request.playbackRate,
      );

      if (await cache.isReady(cacheKey)) {
        final file = await cache.fileFor(cacheKey);
        await cache.markUsed(cacheKey);
        return ExtendedSynthResult.successWith(
          outputFile: file.path,
          durationMs: estimateDurationMs(request.normalizedText),
        );
      }

      // Prepare engine (unloads others if needed for memory)
      final engine = await _prepareEngineForVoice(voiceId);
      if (engine == null) {
        return ExtendedSynthResult.failedWith(
          code: EngineError.modelMissing,
          message: 'No engine available for voice "$voiceId"',
          stage: SynthStage.voiceReady,
        );
      }

      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} synthesizeSegment: starting native synthesis for $voiceId');
      final synthStart = DateTime.now();
      final result = await engine.synthesizeSegment(request);
      final synthTime = DateTime.now().difference(synthStart);
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} synthesizeSegment: native synthesis completed in ${synthTime.inMilliseconds}ms');
      
      return result;
    } finally {
      _activeRequests.remove(request.opId);
    }
  }

  @override
  Future<void> cancelSynth(String requestId) async {
    final voiceId = _activeRequests[requestId];
    if (voiceId != null) {
      final engine = _engineForVoice(voiceId);
      await engine?.cancelSynth(requestId);
    }
  }

  @override
  Future<bool> isVoiceReady(String voiceId) async {
    final engine = _engineForVoice(voiceId);
    if (engine == null) return false;
    return engine.isVoiceReady(voiceId);
  }

  @override
  Future<int> getLoadedModelCount() async {
    var count = 0;
    if (kokoroEngine != null) count += await kokoroEngine!.getLoadedModelCount();
    if (piperEngine != null) count += await piperEngine!.getLoadedModelCount();
    if (supertonicEngine != null) count += await supertonicEngine!.getLoadedModelCount();
    return count;
  }

  @override
  Future<void> unloadLeastUsedModel() async {
    // Unload from the engine with the most loaded models
    var maxEngine = kokoroEngine;
    var maxCount = 0;

    for (final engine in [kokoroEngine, piperEngine, supertonicEngine]) {
      if (engine != null) {
        final count = await engine.getLoadedModelCount();
        if (count > maxCount) {
          maxCount = count;
          maxEngine = engine;
        }
      }
    }

    if (maxEngine != null && maxCount > 0) {
      await maxEngine.unloadLeastUsedModel();
    }
  }

  @override
  Future<void> clearAllModels() async {
    await Future.wait([
      if (kokoroEngine != null) kokoroEngine!.clearAllModels(),
      if (piperEngine != null) piperEngine!.clearAllModels(),
      if (supertonicEngine != null) supertonicEngine!.clearAllModels(),
    ]);
  }

  @override
  Future<void> dispose() async {
    // Clean up all readiness stream controllers
    for (final coreId in _readinessControllers.keys.toList()) {
      _cleanupReadinessSubscriptions(coreId);
    }
    _readinessControllers.clear();
    _readinessSubscriptions.clear();
    
    await Future.wait([
      if (piperEngine != null) piperEngine!.dispose(),
      if (supertonicEngine != null) supertonicEngine!.dispose(),
      if (kokoroEngine != null) kokoroEngine!.dispose(),
    ]);
    _activeRequests.clear();
  }

  /// Get the engine for a specific voice ID.
  AiVoiceEngine? _engineForVoice(String voiceId) {
    if (VoiceIds.isPiper(voiceId)) return piperEngine;
    if (VoiceIds.isSupertonic(voiceId)) return supertonicEngine;
    if (VoiceIds.isKokoro(voiceId)) return kokoroEngine;
    return null;
  }
  
  /// Get the engine type for a voice ID.
  EngineType? _engineTypeForVoice(String voiceId) {
    if (VoiceIds.isPiper(voiceId)) return EngineType.piper;
    if (VoiceIds.isSupertonic(voiceId)) return EngineType.supertonic;
    if (VoiceIds.isKokoro(voiceId)) return EngineType.kokoro;
    return null;
  }
  
  /// Get engine adapter by type.
  AiVoiceEngine? _engineByType(EngineType type) {
    switch (type) {
      case EngineType.piper:
        return piperEngine;
      case EngineType.supertonic:
        return supertonicEngine;
      case EngineType.kokoro:
        return kokoroEngine;
      default:
        return null;
    }
  }
  
  /// Prepare engine for synthesis with memory management.
  /// 
  /// Unloads other engines if needed to stay within memory limits.
  /// Serialized with a lock to prevent concurrent model loading which
  /// can cause OOM crashes on iOS due to doubled memory usage.
  Future<AiVoiceEngine?> _prepareEngineForVoice(String voiceId) async {
    // Wait for any existing preparation to complete first
    // This prevents concurrent model loading which doubles memory usage
    while (_prepareLock != null) {
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _prepareEngineForVoice($voiceId) waiting for lock...');
      await _prepareLock!.future;
    }
    
    // Acquire lock
    _prepareLock = Completer<void>();
    
    try {
      final startTime = DateTime.now();
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _prepareEngineForVoice($voiceId) started');
      
      final engineType = _engineTypeForVoice(voiceId);
      if (engineType == null) {
        debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _prepareEngineForVoice: no engine type for voice');
        return null;
      }
      
      final engine = _engineByType(engineType);
      if (engine == null) {
        debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _prepareEngineForVoice: no engine instance for type');
        return null;
      }
      
      // Prepare memory - may unload other engines
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _prepareEngineForVoice: calling memoryManager.prepareForEngine(${engineType.name})...');
      final prepareStart = DateTime.now();
      await _memoryManager.prepareForEngine(
        engineType,
        unloadCallback: _unloadEngine,
      );
      final prepareTime = DateTime.now().difference(prepareStart);
      final totalTime = DateTime.now().difference(startTime);
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _prepareEngineForVoice: prepareForEngine completed in ${prepareTime.inMilliseconds}ms (total: ${totalTime.inMilliseconds}ms)');
      
      return engine;
    } finally {
      // Release lock
      final completer = _prepareLock;
      _prepareLock = null;
      completer?.complete();
    }
  }
  
  /// Unload an engine by type to free memory.
  Future<void> _unloadEngine(EngineType engineType) async {
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _unloadEngine(${engineType.name}) started');
    final startTime = DateTime.now();
    
    final engine = _engineByType(engineType);
    if (engine == null) {
      debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _unloadEngine: no engine for type, skipping');
      return;
    }
    
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _unloadEngine: calling clearAllModels on ${engineType.name}...');
    final clearStart = DateTime.now();
    await engine.clearAllModels();
    final clearTime = DateTime.now().difference(clearStart);
    final totalTime = DateTime.now().difference(startTime);
    debugPrint('[RoutingEngine] ${DateTime.now().toIso8601String()} _unloadEngine(${engineType.name}) completed in ${clearTime.inMilliseconds}ms (total: ${totalTime.inMilliseconds}ms)');
  }

  /// Synthesize with caching support (convenience method).
  ///
  /// This is the primary method for playback integration.
  Future<SynthResult> synthesizeToWavFile({
    required String voiceId,
    required String text,
    required double playbackRate,
  }) async {
    // Use rate-independent synthesis
    final synthRate = CacheKeyGenerator.getSynthesisRate(playbackRate);

    final cacheKey = CacheKeyGenerator.generate(
      voiceId: voiceId,
      text: text,
      playbackRate: synthRate,
    );

    final outFile = await cache.fileFor(cacheKey);

    return synthesizeToFile(SynthRequest(
      voiceId: voiceId,
      text: text,
      playbackRate: synthRate,
      outFile: outFile,
    ));
  }
}
