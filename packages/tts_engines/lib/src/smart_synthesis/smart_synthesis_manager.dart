import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';

import '../cache/audio_cache.dart';
import '../adapters/routing_engine.dart';

/// Result of pre-synthesis preparation
class PreparationResult {
  const PreparationResult({
    required this.segmentsPrepared,
    required this.totalTimeMs,
    this.errors = const [],
  });

  /// Number of segments successfully pre-synthesized
  final int segmentsPrepared;

  /// Total preparation time in milliseconds
  final int totalTimeMs;

  /// Any errors encountered during preparation
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => segmentsPrepared > 0 && !hasErrors;
}

/// Device performance tier for adaptive configuration
enum DeviceTier {
  flagship,  // <0.3 RTF
  midRange,  // 0.3-0.5 RTF
  budget,    // 0.5-0.8 RTF
  legacy,    // >0.8 RTF
}

/// Configuration for smart synthesis behavior
class EngineConfig {
  const EngineConfig({
    required this.prefetchWindowSegments,
    required this.maxConcurrentSynthesis,
    required this.coldStartSegments,
    this.preloadOnOpen = true,
    this.immediateSecondSegment = false,
    this.preSynthesisRequired = false,
  });

  /// How many segments ahead to prefetch during playback
  final int prefetchWindowSegments;

  /// Maximum number of parallel synthesis operations
  final int maxConcurrentSynthesis;

  /// Number of segments to pre-synthesize before playback starts
  final int coldStartSegments;

  /// Whether to pre-synthesize when opening a book/chapter
  final bool preloadOnOpen;

  /// Start second segment synthesis immediately after first (Piper-specific)
  final bool immediateSecondSegment;

  /// Requires full chapter pre-synthesis (Kokoro fallback)
  final bool preSynthesisRequired;
}

/// Abstract manager for intelligent audio pre-synthesis and prefetch strategies
abstract class SmartSynthesisManager {
  /// Called when user opens a book or navigates to chapter
  /// Pre-synthesizes first segment(s) to eliminate cold start buffering
  Future<PreparationResult> prepareForPlayback({
    required RoutingEngine engine,
    required AudioCache cache,
    required List<AudioTrack> tracks,
    required String voiceId,
    required double playbackRate,
    int startIndex = 0,
  });

  /// Get engine-specific configuration for given device tier
  EngineConfig getConfig(DeviceTier tier);

  /// Measure synthesis Real-Time Factor (RTF) for device profiling
  /// Returns ratio of synthesis_time / audio_duration
  /// RTF < 1.0 means synthesis is faster than real-time
  Future<double> measureRTF({
    required RoutingEngine engine,
    required String voiceId,
    String testText = 'This is a test sentence for measuring synthesis performance on your device.',
  }) async {
    developer.log('[$runtimeType] Measuring RTF for voice: $voiceId');

    final synthStart = DateTime.now();
    final result = await engine.synthesizeToWavFile(
      voiceId: voiceId,
      text: testText,
      playbackRate: 1.0,
    );
    final synthDuration = DateTime.now().difference(synthStart);

    final rtf = synthDuration.inMilliseconds / result.durationMs;
    developer.log('[$runtimeType] RTF = ${rtf.toStringAsFixed(2)}x (${synthDuration.inMilliseconds}ms synth / ${result.durationMs}ms audio)');

    return rtf;
  }

  /// Classify device tier based on measured RTF
  DeviceTier classifyDeviceTier(double rtf) {
    if (rtf < 0.3) return DeviceTier.flagship;
    if (rtf < 0.5) return DeviceTier.midRange;
    if (rtf < 0.8) return DeviceTier.budget;
    return DeviceTier.legacy;
  }
}
