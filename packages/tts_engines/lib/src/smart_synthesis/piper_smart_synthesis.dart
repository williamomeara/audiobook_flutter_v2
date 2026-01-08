import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';

import '../cache/audio_cache.dart';
import '../adapters/routing_engine.dart';
import 'smart_synthesis_manager.dart';

/// Smart synthesis implementation for Piper TTS engine
///
/// Piper characteristics:
/// - RTF: ~0.38x (fast)
/// - Buffering: 9.8s (2 events - first 7.4s + second 2.4s)
/// - Strategy: Pre-synthesize first segment + immediately start second (non-blocking)
///            to eliminate 100% of buffering
class PiperSmartSynthesis extends SmartSynthesisManager {
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
      '🎤 [PiperSmartSynthesis] Preparing for playback: '
      '${tracks.length} tracks, starting at index $startIndex',
    );

    final prepStart = DateTime.now();
    final errors = <String>[];
    var segmentsPrepared = 0;

    try {
      // Phase 1: Pre-synthesize first segment (blocking)
      // This eliminates 75% of buffering (first 7.4s wait)
      final firstTrack = tracks[startIndex];

      developer.log(
        '🔄 [PiperSmartSynthesis] Pre-synthesizing first segment: '
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
        '✅ [PiperSmartSynthesis] First segment ready in ${synthDuration.inMilliseconds}ms '
        '(${result.durationMs}ms audio)',
      );

      segmentsPrepared = 1;

      // Phase 2: Immediately start second segment synthesis (non-blocking)
      // This fixes the second-segment 2.4s buffering issue
      if (tracks.length > startIndex + 1) {
        final secondTrack = tracks[startIndex + 1];
        developer.log(
          '🚀 [PiperSmartSynthesis] Starting second segment immediately (non-blocking)',
        );
        
        // Fire and forget - don't await, let it synthesize while user reads
        _synthesizeInBackground(
          engine: engine,
          voiceId: voiceId,
          text: secondTrack.text,
          playbackRate: playbackRate,
          segmentIndex: startIndex + 1,
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ [PiperSmartSynthesis] Pre-synthesis failed',
        error: e,
        stackTrace: stackTrace,
      );
      errors.add(e.toString());
    }

    final totalTime = DateTime.now().difference(prepStart);

    developer.log(
      '🎉 [PiperSmartSynthesis] Preparation complete: '
      '$segmentsPrepared segments in ${totalTime.inMilliseconds}ms '
      '(second segment synthesizing in background)',
    );

    return PreparationResult(
      segmentsPrepared: segmentsPrepared,
      totalTimeMs: totalTime.inMilliseconds,
      errors: errors,
    );
  }

  /// Synthesize a segment in the background without blocking
  Future<void> _synthesizeInBackground({
    required RoutingEngine engine,
    required String voiceId,
    required String text,
    required double playbackRate,
    required int segmentIndex,
  }) async {
    try {
      final synthStart = DateTime.now();
      final result = await engine.synthesizeToWavFile(
        voiceId: voiceId,
        text: text,
        playbackRate: playbackRate,
      );
      final synthDuration = DateTime.now().difference(synthStart);
      
      developer.log(
        '✅ [PiperSmartSynthesis] Background segment $segmentIndex ready in '
        '${synthDuration.inMilliseconds}ms (${result.durationMs}ms audio)',
      );
    } catch (e, stackTrace) {
      developer.log(
        '⚠️ [PiperSmartSynthesis] Background synthesis failed for segment $segmentIndex',
        error: e,
        stackTrace: stackTrace,
      );
      // Don't rethrow - background failure is non-critical
      // Playback will fall back to JIT synthesis for this segment
    }
  }

  @override
  EngineConfig getConfig(DeviceTier tier) {
    // Piper is fast (RTF 0.38x) but slightly slower than Supertonic
    // Adjust prefetch window accordingly
    switch (tier) {
      case DeviceTier.flagship:
        return const EngineConfig(
          prefetchWindowSegments: 3,      // Prefetch 3 segments ahead
          maxConcurrentSynthesis: 2,      // 2x parallel synthesis
          coldStartSegments: 1,           // Only block on first segment
          preloadOnOpen: true,
          immediateSecondSegment: true,   // Piper-specific: start second immediately
        );
      case DeviceTier.midRange:
        return const EngineConfig(
          prefetchWindowSegments: 2,      // Prefetch 2 segments ahead
          maxConcurrentSynthesis: 2,      // Still allow 2x parallel
          coldStartSegments: 1,
          preloadOnOpen: true,
          immediateSecondSegment: true,
        );
      case DeviceTier.budget:
        return const EngineConfig(
          prefetchWindowSegments: 2,      // 2 ahead
          maxConcurrentSynthesis: 1,      // Single-threaded
          coldStartSegments: 1,
          preloadOnOpen: true,
          immediateSecondSegment: true,   // Still important for Piper
        );
      case DeviceTier.legacy:
        return const EngineConfig(
          prefetchWindowSegments: 1,      // Conservative
          maxConcurrentSynthesis: 1,
          coldStartSegments: 1,
          preloadOnOpen: true,
          immediateSecondSegment: false,  // Too slow for background synthesis
        );
    }
  }
}
