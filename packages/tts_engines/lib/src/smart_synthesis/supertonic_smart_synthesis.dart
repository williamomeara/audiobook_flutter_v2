import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';

import '../cache/audio_cache.dart';
import '../adapters/routing_engine.dart';
import 'smart_synthesis_manager.dart';

/// Smart synthesis implementation for Supertonic TTS engine
///
/// Supertonic characteristics:
/// - RTF: ~0.26x (very fast)
/// - Buffering: 5.2s (1 event - first segment only)
/// - Strategy: Pre-synthesize first segment → 100% buffering elimination
class SupertonicSmartSynthesis extends SmartSynthesisManager {
  @override
  Future<PreparationResult> prepareForPlayback({
    required RoutingEngine engine,
    required AudioCache cache,
    required List<AudioTrack> tracks,
    required String voiceId,
    required double playbackRate,
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) {
      return PreparationResult(
        segmentsPrepared: 0,
        totalTimeMs: 0,
        errors: ['No tracks provided'],
      );
    }

    developer.log(
      '🎤 [SupertonicSmartSynthesis] Preparing for playback: '
      '${tracks.length} tracks, starting at index $startIndex',
    );

    final prepStart = DateTime.now();
    final errors = <String>[];
    var segmentsPrepared = 0;

    try {
      // Pre-synthesize ONLY the first segment
      // This eliminates 100% of buffering for Supertonic (only 1 buffering event)
      final firstTrack = tracks[startIndex];

      developer.log(
        '🔄 [SupertonicSmartSynthesis] Pre-synthesizing first segment: '
        '"${firstTrack.text.substring(0, firstTrack.text.length.clamp(0, 50))}..."',
      );

      final synthStart = DateTime.now();
      final result = await engine.synthesizeToWavFile(
        voiceId: voiceId,
        text: firstTrack.text,
        playbackRate: playbackRate,
      );
      final synthDuration = DateTime.now().difference(synthStart);

      developer.log(
        '✅ [SupertonicSmartSynthesis] First segment ready in ${synthDuration.inMilliseconds}ms '
        '(${result.durationMs}ms audio)',
      );

      segmentsPrepared = 1;
    } catch (e, stackTrace) {
      developer.log(
        '❌ [SupertonicSmartSynthesis] Pre-synthesis failed',
        error: e,
        stackTrace: stackTrace,
      );
      errors.add(e.toString());
    }

    final totalTime = DateTime.now().difference(prepStart);

    developer.log(
      '🎉 [SupertonicSmartSynthesis] Preparation complete: '
      '$segmentsPrepared segments in ${totalTime.inMilliseconds}ms',
    );

    return PreparationResult(
      segmentsPrepared: segmentsPrepared,
      totalTimeMs: totalTime.inMilliseconds,
      errors: errors,
    );
  }

  @override
  EngineConfig getConfig(DeviceTier tier) {
    // Supertonic is so fast (RTF 0.26x) that we can be aggressive
    // even on mid-range devices
    switch (tier) {
      case DeviceTier.flagship:
        return const EngineConfig(
          prefetchWindowSegments: 3,      // Prefetch 3 segments ahead
          maxConcurrentSynthesis: 2,      // 2x parallel synthesis
          coldStartSegments: 1,           // Only first segment needed
          preloadOnOpen: true,
        );
      case DeviceTier.midRange:
        return const EngineConfig(
          prefetchWindowSegments: 2,      // Prefetch 2 segments ahead
          maxConcurrentSynthesis: 2,      // Still allow 2x parallel
          coldStartSegments: 1,
          preloadOnOpen: true,
        );
      case DeviceTier.budget:
        return const EngineConfig(
          prefetchWindowSegments: 2,      // Still 2 ahead
          maxConcurrentSynthesis: 1,      // Single-threaded
          coldStartSegments: 1,
          preloadOnOpen: true,
        );
      case DeviceTier.legacy:
        return const EngineConfig(
          prefetchWindowSegments: 1,      // Conservative
          maxConcurrentSynthesis: 1,
          coldStartSegments: 1,
          preloadOnOpen: true,
        );
    }
  }
}
