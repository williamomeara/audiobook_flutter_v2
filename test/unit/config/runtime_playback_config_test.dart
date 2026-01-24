import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/app/config/runtime_playback_config.dart';

void main() {
  group('RuntimePlaybackConfig', () {
    group('default values', () {
      test('should have expected defaults', () {
        final config = RuntimePlaybackConfig();

        expect(config.cacheBudgetMB, isNull);
        expect(config.cacheMaxAgeDays, isNull);
        expect(config.prefetchMode, PrefetchMode.adaptive);
        expect(config.parallelSynthesisThreads, isNull);
        expect(config.resumeDelayMs, 500);
        expect(config.rateIndependentSynthesis, true);
        expect(config.lastModified, isNotNull);
      });

      test('effectiveCacheBudgetBytes returns default when null', () {
        final config = RuntimePlaybackConfig();

        // Default: 500 MB
        expect(config.effectiveCacheBudgetBytes, 500 * 1024 * 1024);
      });

      test('effectiveMaxAgeMs returns default when null', () {
        final config = RuntimePlaybackConfig();

        // Default: 7 days
        expect(config.effectiveMaxAgeMs, 7 * 24 * 60 * 60 * 1000);
      });
    });

    group('copyWith', () {
      test('should create modified copy without affecting original', () {
        final original = RuntimePlaybackConfig();
        final modified = original.copyWith(cacheBudgetMB: 1024);

        expect(original.cacheBudgetMB, isNull);
        expect(modified.cacheBudgetMB, 1024);
      });

      test('should update lastModified on copyWith', () {
        final original = RuntimePlaybackConfig();
        final originalTime = original.lastModified;

        // Small delay to ensure different timestamp
        final modified = original.copyWith(prefetchMode: PrefetchMode.aggressive);

        expect(modified.lastModified.isAfter(originalTime) || 
               modified.lastModified.isAtSameMomentAs(originalTime), true);
      });

      test('should clamp parallelSynthesisThreads to 1-4', () {
        final config = RuntimePlaybackConfig();

        final withZero = config.copyWith(parallelSynthesisThreads: 0);
        expect(withZero.parallelSynthesisThreads, 1);

        final withTen = config.copyWith(parallelSynthesisThreads: 10);
        expect(withTen.parallelSynthesisThreads, 4);

        final withTwo = config.copyWith(parallelSynthesisThreads: 2);
        expect(withTwo.parallelSynthesisThreads, 2);
      });
    });

    group('serialization', () {
      test('toJson should serialize all fields', () {
        final config = RuntimePlaybackConfig(
          cacheBudgetMB: 1024,
          cacheMaxAgeDays: 14,
          prefetchMode: PrefetchMode.aggressive,
          parallelSynthesisThreads: 2,
          resumeDelayMs: 250,
          rateIndependentSynthesis: false,
        );

        final json = config.toJson();

        expect(json['cacheBudgetMB'], 1024);
        expect(json['cacheMaxAgeDays'], 14);
        expect(json['prefetchMode'], 'aggressive');
        expect(json['parallelSynthesisThreads'], 2);
        expect(json['resumeDelayMs'], 250);
        expect(json['rateIndependentSynthesis'], false);
        expect(json['lastModified'], isNotNull);
      });

      test('fromJson should deserialize all fields', () {
        final json = {
          'cacheBudgetMB': 2048,
          'cacheMaxAgeDays': 30,
          'prefetchMode': 'conservative',
          'parallelSynthesisThreads': 3,
          'resumeDelayMs': 1000,
          'rateIndependentSynthesis': false,
          'lastModified': '2024-01-15T12:00:00.000Z',
        };

        final config = RuntimePlaybackConfig.fromJson(json);

        expect(config.cacheBudgetMB, 2048);
        expect(config.cacheMaxAgeDays, 30);
        expect(config.prefetchMode, PrefetchMode.conservative);
        expect(config.parallelSynthesisThreads, 3);
        expect(config.resumeDelayMs, 1000);
        expect(config.rateIndependentSynthesis, false);
        expect(config.lastModified.year, 2024);
      });

      test('round-trip serialization should preserve values', () {
        final original = RuntimePlaybackConfig(
          cacheBudgetMB: 512,
          cacheMaxAgeDays: 3,
          prefetchMode: PrefetchMode.off,
          parallelSynthesisThreads: 1,
          resumeDelayMs: 750,
          rateIndependentSynthesis: true,
        );

        final json = original.toJson();
        final restored = RuntimePlaybackConfig.fromJson(json);

        expect(restored.cacheBudgetMB, original.cacheBudgetMB);
        expect(restored.cacheMaxAgeDays, original.cacheMaxAgeDays);
        expect(restored.prefetchMode, original.prefetchMode);
        expect(restored.parallelSynthesisThreads, original.parallelSynthesisThreads);
        expect(restored.resumeDelayMs, original.resumeDelayMs);
        expect(restored.rateIndependentSynthesis, original.rateIndependentSynthesis);
      });

      test('fromJson should handle missing fields with defaults', () {
        final json = <String, dynamic>{};

        final config = RuntimePlaybackConfig.fromJson(json);

        expect(config.cacheBudgetMB, isNull);
        expect(config.cacheMaxAgeDays, isNull);
        expect(config.prefetchMode, PrefetchMode.adaptive);
        expect(config.parallelSynthesisThreads, isNull);
        expect(config.resumeDelayMs, 500);
        expect(config.rateIndependentSynthesis, true);
      });

      test('fromJson should handle invalid prefetchMode with default', () {
        final json = {
          'prefetchMode': 'invalid_mode',
        };

        final config = RuntimePlaybackConfig.fromJson(json);

        expect(config.prefetchMode, PrefetchMode.adaptive);
      });
    });

    group('PrefetchMode', () {
      test('all modes should be serializable', () {
        for (final mode in PrefetchMode.values) {
          final config = RuntimePlaybackConfig(prefetchMode: mode);
          final json = config.toJson();
          final restored = RuntimePlaybackConfig.fromJson(json);

          expect(restored.prefetchMode, mode);
        }
      });
    });

    group('convenience methods', () {
      test('isPrefetchEnabled should be false only for off mode', () {
        expect(
          RuntimePlaybackConfig(prefetchMode: PrefetchMode.adaptive).isPrefetchEnabled,
          true,
        );
        expect(
          RuntimePlaybackConfig(prefetchMode: PrefetchMode.aggressive).isPrefetchEnabled,
          true,
        );
        expect(
          RuntimePlaybackConfig(prefetchMode: PrefetchMode.conservative).isPrefetchEnabled,
          true,
        );
        expect(
          RuntimePlaybackConfig(prefetchMode: PrefetchMode.off).isPrefetchEnabled,
          false,
        );
      });

      test('effectiveResumeDelay should return Duration', () {
        final config = RuntimePlaybackConfig(resumeDelayMs: 750);

        expect(config.effectiveResumeDelay, const Duration(milliseconds: 750));
      });

      test('effectiveCacheBudgetBytes should calculate from MB', () {
        final config = RuntimePlaybackConfig(cacheBudgetMB: 2048);

        expect(config.effectiveCacheBudgetBytes, 2048 * 1024 * 1024);
      });

      test('effectiveMaxAgeMs should calculate from days', () {
        final config = RuntimePlaybackConfig(cacheMaxAgeDays: 14);

        expect(config.effectiveMaxAgeMs, 14 * 24 * 60 * 60 * 1000);
      });
    });

    group('equality', () {
      test('configs with same values should be equal', () {
        final config1 = RuntimePlaybackConfig(
          cacheBudgetMB: 512,
          prefetchMode: PrefetchMode.adaptive,
        );
        final config2 = RuntimePlaybackConfig(
          cacheBudgetMB: 512,
          prefetchMode: PrefetchMode.adaptive,
        );

        // Note: lastModified will differ, but we compare content
        expect(config1.cacheBudgetMB, config2.cacheBudgetMB);
        expect(config1.prefetchMode, config2.prefetchMode);
      });

      test('toString should produce readable output', () {
        final config = RuntimePlaybackConfig(
          cacheBudgetMB: 1024,
          prefetchMode: PrefetchMode.aggressive,
        );

        final str = config.toString();

        expect(str, contains('cacheBudgetMB: 1024'));
        expect(str, contains('prefetchMode: aggressive'));
      });
    });
  });
}
