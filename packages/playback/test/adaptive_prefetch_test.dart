import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

void main() {
  group('AdaptivePrefetchConfig', () {
    group('calculatePrefetchWindow', () {
      test('should return 0 when mode is off', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.off);

        final window = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        expect(window, 0);
      });

      test('should return max 2 when mode is conservative', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.conservative);

        final window = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.aggressive,
          isCharging: true,
          memoryPressure: MemoryPressure.none,
        );

        expect(window, 2);
      });

      test('should not exceed remaining segments', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.aggressive);

        final window = config.calculatePrefetchWindow(
          queueLength: 5,
          currentPosition: 3, // Only 2 remaining
          measuredRTF: 0.2,
          synthesisMode: SynthesisMode.aggressive,
          isCharging: true,
          memoryPressure: MemoryPressure.none,
        );

        expect(window, 2); // Can't exceed remaining
      });

      test('should return 0 when no remaining segments', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final window = config.calculatePrefetchWindow(
          queueLength: 10,
          currentPosition: 10, // At end
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        expect(window, 0);
      });

      test('should increase window for fast RTF (< 0.3)', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final normalRTF = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.6,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        final fastRTF = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.2, // Fast synthesis
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        expect(fastRTF, greaterThan(normalRTF));
      });

      test('should decrease window for slow RTF (> 1.0)', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final normalRTF = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.6,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        final slowRTF = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 1.5, // Slow synthesis
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        expect(slowRTF, lessThan(normalRTF));
      });

      test('should increase window when charging', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final notCharging = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        final charging = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: true,
          memoryPressure: MemoryPressure.none,
        );

        expect(charging, greaterThan(notCharging));
      });

      test('should decrease window under memory pressure', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final noPressure = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        final moderatePressure = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.moderate,
        );

        final criticalPressure = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.critical,
        );

        expect(moderatePressure, lessThan(noPressure));
        expect(criticalPressure, lessThan(moderatePressure));
      });

      test('should always return at least 1 when prefetch enabled', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final window = config.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 10.0, // Very slow
          synthesisMode: SynthesisMode.jitOnly,
          isCharging: false,
          memoryPressure: MemoryPressure.critical,
        );

        // jitOnly mode has maxPrefetchTracks = 0, so result should be at least 1
        // (minimum guarantee when prefetch mode is not off)
        expect(window, greaterThanOrEqualTo(1));
      });

      test('aggressive mode should have larger window than adaptive', () {
        final adaptiveConfig = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);
        final aggressiveConfig = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.aggressive);

        final adaptive = adaptiveConfig.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        final aggressive = aggressiveConfig.calculatePrefetchWindow(
          queueLength: 100,
          currentPosition: 0,
          measuredRTF: 0.5,
          synthesisMode: SynthesisMode.balanced,
          isCharging: false,
          memoryPressure: MemoryPressure.none,
        );

        expect(aggressive, greaterThan(adaptive));
      });
    });

    group('calculateBufferTargetMs', () {
      test('should return 0 when mode is off', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.off);

        final target = config.calculateBufferTargetMs(
          synthesisMode: SynthesisMode.balanced,
          measuredRTF: 0.5,
          memoryPressure: MemoryPressure.none,
        );

        expect(target, 0);
      });

      test('should return at least 10 seconds minimum', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.conservative);

        final target = config.calculateBufferTargetMs(
          synthesisMode: SynthesisMode.jitOnly,
          measuredRTF: 1.5,
          memoryPressure: MemoryPressure.critical,
        );

        expect(target, greaterThanOrEqualTo(10000));
      });

      test('should reduce target under memory pressure', () {
        final config = AdaptivePrefetchConfig(prefetchMode: PrefetchMode.adaptive);

        final noPressure = config.calculateBufferTargetMs(
          synthesisMode: SynthesisMode.balanced,
          measuredRTF: 0.5,
          memoryPressure: MemoryPressure.none,
        );

        final criticalPressure = config.calculateBufferTargetMs(
          synthesisMode: SynthesisMode.balanced,
          measuredRTF: 0.5,
          memoryPressure: MemoryPressure.critical,
        );

        expect(criticalPressure, lessThan(noPressure));
      });
    });

    group('estimateSynthesisTime', () {
      test('should estimate based on RTF and segment count', () {
        final config = AdaptivePrefetchConfig();

        final estimate = config.estimateSynthesisTime(
          segmentCount: 5,
          avgSegmentDurationSec: 10.0,
          measuredRTF: 0.5,
        );

        // 5 segments * 10 seconds * 0.5 RTF = 25 seconds
        expect(estimate.inSeconds, 25);
      });

      test('should return default estimate when RTF is 0', () {
        final config = AdaptivePrefetchConfig();

        final estimate = config.estimateSynthesisTime(
          segmentCount: 5,
          avgSegmentDurationSec: 10.0,
          measuredRTF: 0,
        );

        // Default: 5 seconds per segment
        expect(estimate.inSeconds, 25);
      });
    });
  });
}
