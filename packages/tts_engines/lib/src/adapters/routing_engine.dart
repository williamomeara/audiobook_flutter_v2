import 'dart:async';

import 'package:core_domain/core_domain.dart';

import '../interfaces/ai_voice_engine.dart';
import '../interfaces/segment_synth_request.dart';
import '../interfaces/synth_request.dart';
import '../interfaces/synth_result.dart';
import '../interfaces/tts_state_machines.dart';
import '../cache/audio_cache.dart';

/// Routes synthesis requests to the appropriate voice engine.
///
/// This is the main entry point for synthesis. It:
/// 1. Checks the cache for existing audio
/// 2. Routes to the correct engine based on voice ID
/// 3. Caches the result for future use
class RoutingEngine implements AiVoiceEngine {
  RoutingEngine({
    required this.cache,
    this.piperEngine,
    this.supertonicEngine,
    this.kokoroEngine,
  });

  /// Audio cache for storing synthesized files.
  final AudioCache cache;

  /// Piper TTS engine adapter.
  final AiVoiceEngine? piperEngine;

  /// Supertonic TTS engine adapter.
  final AiVoiceEngine? supertonicEngine;

  /// Kokoro TTS engine adapter.
  final AiVoiceEngine? kokoroEngine;

  /// Track active requests for cancellation.
  final Map<String, String> _activeRequests = {};

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
  Future<CoreReadiness> getCoreReadiness(String voiceId) async {
    final engine = _engineForVoice(voiceId);
    if (engine == null) {
      return CoreReadiness.failedWith('unknown', 'No engine for voice $voiceId');
    }
    return engine.getCoreReadiness(voiceId);
  }

  @override
  Stream<CoreReadiness> watchCoreReadiness(String coreId) {
    // Aggregate from all engines
    final controller = StreamController<CoreReadiness>.broadcast();
    
    void addFromEngine(AiVoiceEngine? engine) {
      if (engine != null) {
        engine.watchCoreReadiness(coreId).listen(controller.add);
      }
    }
    
    addFromEngine(kokoroEngine);
    addFromEngine(piperEngine);
    addFromEngine(supertonicEngine);
    
    return controller.stream;
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
      return SynthResult(file: file, durationMs: durationMs);
    }

    // Route to appropriate engine
    final engine = _engineForVoice(voiceId);
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

      final engine = _engineForVoice(voiceId);
      if (engine == null) {
        return ExtendedSynthResult.failedWith(
          code: EngineError.modelMissing,
          message: 'No engine available for voice "$voiceId"',
          stage: SynthStage.voiceReady,
        );
      }

      return await engine.synthesizeSegment(request);
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
