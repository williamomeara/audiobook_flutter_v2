import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';

import 'engine_config.dart';

/// Profiles device performance by running synthesis benchmarks.
///
/// This profiler measures the Real-Time Factor (RTF) for a specific engine
/// on the current device, which is used to determine optimal prefetch settings.
class DevicePerformanceProfiler {
  DevicePerformanceProfiler({
    this.sampleSegmentCount = 3,
    this.warmupSegmentCount = 1,
  });

  /// Number of segments to synthesize for profiling.
  final int sampleSegmentCount;

  /// Number of warmup segments (not counted in measurements).
  final int warmupSegmentCount;

  /// Test sentences for profiling (varied length and complexity).
  static const _testSentences = [
    'The quick brown fox jumps over the lazy dog near the riverbank.',
    'She sells seashells by the seashore on sunny summer afternoons.',
    'How much wood would a woodchuck chuck if a woodchuck could chuck wood?',
    'Peter Piper picked a peck of pickled peppers for the party.',
    'The rain in Spain stays mainly in the plain during the spring.',
    'All good things must come to an end, but new beginnings await us.',
    'A journey of a thousand miles begins with a single step forward.',
    'The early bird catches the worm, but the second mouse gets the cheese.',
    'Actions speak louder than words, and silence speaks volumes too.',
    'When life gives you lemons, make lemonade and share it with friends.',
    'Every cloud has a silver lining, even on the darkest of days.',
    'Time flies when you are having fun with good company and laughter.',
  ];

  /// Generate unique test texts to avoid cache hits.
  /// Appends a unique identifier to each sentence.
  List<String> _generateUniqueTestTexts(int timestamp) {
    return _testSentences.map((sentence) {
      // Append unique ID at the end - natural sounding and ensures no cache hit
      return '$sentence Test run number $timestamp.';
    }).toList();
  }

  /// Get engine ID from voice ID.
  /// 
  /// Profiles are stored per-engine (piper, kokoro, supertonic) not per-voice,
  /// since all voices of an engine have similar performance characteristics.
  static String engineIdFromVoice(String voiceId) {
    final engine = VoiceIds.engineFor(voiceId);
    return engine.name; // Returns 'piper', 'kokoro', 'supertonic', 'device'
  }

  /// Run performance profiling for an engine.
  ///
  /// This synthesizes several test segments and measures synthesis time
  /// vs audio duration to calculate RTF.
  /// 
  /// Note: Uses randomized text with timestamp to avoid cache hits.
  /// Note: Profile is stored per-engine, not per-voice.
  Future<DeviceProfile> profileEngine({
    required RoutingEngine engine,
    required String voiceId,
    required double playbackRate,
    void Function(int current, int total)? onProgress,
  }) async {
    final engineId = engineIdFromVoice(voiceId);
    print('[Profiler] Starting device profiling for engine: $engineId (voice: $voiceId)');
    print('[Profiler] Warmup: $warmupSegmentCount, Samples: $sampleSegmentCount');
    
    // Generate unique test texts to avoid cache hits
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final testTexts = _generateUniqueTestTexts(timestamp);

    // Warmup - don't count these (first runs are slower)
    for (var i = 0; i < warmupSegmentCount; i++) {
      final text = testTexts[i % testTexts.length];
      try {
        await engine.synthesizeToWavFile(
          voiceId: voiceId,
          text: text,
          playbackRate: playbackRate,
        );
      } catch (e) {
        print('[Profiler] Warmup $i failed: $e');
      }
    }
    print('[Profiler] Warmup complete');

    // Measure synthesis performance
    final synthesisTimesMs = <int>[];
    final audioDurationsMs = <int>[];

    for (var i = 0; i < sampleSegmentCount; i++) {
      final text = testTexts[(warmupSegmentCount + i) % testTexts.length];
      onProgress?.call(i + 1, sampleSegmentCount);

      try {
        final startTime = DateTime.now();
        await engine.synthesizeToWavFile(
          voiceId: voiceId,
          text: text,
          playbackRate: playbackRate,
        );
        final synthTimeMs = DateTime.now().difference(startTime).inMilliseconds;
        synthesisTimesMs.add(synthTimeMs);

        // Estimate audio duration based on word count (~150 WPM speaking rate)
        final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final estimatedDurationMs = (wordCount / 150 * 60 * 1000).round();
        audioDurationsMs.add(estimatedDurationMs);

        print('[Profiler] Segment $i: ${synthTimeMs}ms synth / ${estimatedDurationMs}ms audio');
      } catch (e) {
        print('[Profiler] Segment $i failed: $e');
        // Skip failed segments
      }
    }

    if (synthesisTimesMs.isEmpty) {
      throw Exception('Profiling failed: no successful syntheses');
    }

    // Calculate averages
    final avgSynthMs = synthesisTimesMs.reduce((a, b) => a + b) ~/ synthesisTimesMs.length;
    final avgAudioMs = audioDurationsMs.reduce((a, b) => a + b) ~/ audioDurationsMs.length;
    final rtf = avgAudioMs > 0 ? avgSynthMs / avgAudioMs : 1.0;

    final profile = DeviceProfile(
      engineId: engineId,
      avgSynthesisMs: avgSynthMs,
      avgAudioDurationMs: avgAudioMs,
      rtf: rtf,
      segmentCount: synthesisTimesMs.length,
      profiledAt: DateTime.now(),
    );

    print('[Profiler] ═══════════════════════════════');
    print('[Profiler] PROFILING COMPLETE');
    print('[Profiler] Engine: $engineId');
    print('[Profiler] RTF: ${rtf.toStringAsFixed(3)}');
    print('[Profiler] Tier: ${profile.tier}');
    print('[Profiler] Avg Synthesis: ${avgSynthMs}ms');
    print('[Profiler] Avg Audio: ${avgAudioMs}ms');
    print('[Profiler] ═══════════════════════════════');

    return profile;
  }

  /// Create optimal configuration based on device profile.
  DeviceEngineConfig createConfigFromProfile(DeviceProfile profile) {
    switch (profile.tier) {
      case DevicePerformanceTier.flagship:
        return DeviceEngineConfig.flagship(profile.engineId, profile.rtf);
      case DevicePerformanceTier.midRange:
        return DeviceEngineConfig.midRange(profile.engineId, profile.rtf);
      case DevicePerformanceTier.budget:
        return DeviceEngineConfig.budget(profile.engineId, profile.rtf);
      case DevicePerformanceTier.legacy:
        return DeviceEngineConfig.legacy(profile.engineId, profile.rtf);
    }
  }
}
