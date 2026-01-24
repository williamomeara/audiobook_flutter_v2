import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

void main() {
  group('SynthesisStrategy', () {
    group('fromJson factory', () {
      test('creates AdaptiveSynthesisStrategy for adaptive type', () {
        final json = {'type': 'adaptive'};
        final strategy = SynthesisStrategy.fromJson(json);
        expect(strategy, isA<AdaptiveSynthesisStrategy>());
      });

      test('creates AggressiveSynthesisStrategy for aggressive type', () {
        final json = {'type': 'aggressive'};
        final strategy = SynthesisStrategy.fromJson(json);
        expect(strategy, isA<AggressiveSynthesisStrategy>());
      });

      test('creates ConservativeSynthesisStrategy for conservative type', () {
        final json = {'type': 'conservative'};
        final strategy = SynthesisStrategy.fromJson(json);
        expect(strategy, isA<ConservativeSynthesisStrategy>());
      });

      test('defaults to AdaptiveSynthesisStrategy for unknown type', () {
        final json = {'type': 'unknown'};
        final strategy = SynthesisStrategy.fromJson(json);
        expect(strategy, isA<AdaptiveSynthesisStrategy>());
      });

      test('defaults to AdaptiveSynthesisStrategy for null type', () {
        final json = <String, dynamic>{};
        final strategy = SynthesisStrategy.fromJson(json);
        expect(strategy, isA<AdaptiveSynthesisStrategy>());
      });
    });

    group('fromType factory', () {
      test('creates AdaptiveSynthesisStrategy for adaptive', () {
        final strategy = SynthesisStrategy.fromType(SynthesisStrategyType.adaptive);
        expect(strategy, isA<AdaptiveSynthesisStrategy>());
      });

      test('creates AggressiveSynthesisStrategy for aggressive', () {
        final strategy = SynthesisStrategy.fromType(SynthesisStrategyType.aggressive);
        expect(strategy, isA<AggressiveSynthesisStrategy>());
      });

      test('creates ConservativeSynthesisStrategy for conservative', () {
        final strategy = SynthesisStrategy.fromType(SynthesisStrategyType.conservative);
        expect(strategy, isA<ConservativeSynthesisStrategy>());
      });
    });
  });

  group('AdaptiveSynthesisStrategy', () {
    test('has default values', () {
      final strategy = AdaptiveSynthesisStrategy();
      expect(strategy.preSynthesizeCount, 3);
      expect(strategy.maxConcurrency, 1);
      expect(strategy.avgRtf, 0.5);
      expect(strategy.completedCount, 0);
      expect(strategy.name, 'Adaptive');
    });

    test('restores from JSON with learned values', () {
      final json = {
        'type': 'adaptive',
        'preSynthesizeCount': 5,
        'avgRtf': 0.25,
        'completedCount': 10,
      };
      final strategy = AdaptiveSynthesisStrategy.fromJson(json);
      expect(strategy.preSynthesizeCount, 5);
      expect(strategy.avgRtf, 0.25);
      expect(strategy.completedCount, 10);
    });

    test('serializes to JSON', () {
      final strategy = AdaptiveSynthesisStrategy(
        preSynthesizeCount: 4,
        avgRtf: 0.3,
        completedCount: 7,
      );
      final json = strategy.toJson();
      expect(json['type'], 'adaptive');
      expect(json['preSynthesizeCount'], 4);
      expect(json['avgRtf'], 0.3);
      expect(json['completedCount'], 7);
    });

    group('shouldContinuePrefetch', () {
      late AdaptiveSynthesisStrategy strategy;

      setUp(() {
        strategy = AdaptiveSynthesisStrategy();
      });

      test('returns false when not playing and buffer is high', () {
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 60000, // 1 minute
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: false,
        );
        expect(result, false);
      });

      test('returns true when buffer is critically low', () {
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 5000, // 5 seconds
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: false,
        );
        expect(result, true);
      });

      test('returns false when buffer is above threshold', () {
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 65000, // 65 seconds
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, false);
      });

      test('returns true when buffer is below threshold and playing', () {
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 30000, // 30 seconds
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, true);
      });

      test('returns false when no remaining segments', () {
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 30000,
          remainingSegments: 0,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, false);
      });

      test('uses higher threshold for fast RTF', () {
        // For fast RTF (< 0.5), threshold is 120000ms
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 100000, // 100 seconds - below 120s threshold
          remainingSegments: 10,
          recentRtf: 0.3,
          isPlaying: true,
        );
        expect(result, true);
      });
    });

    group('onSynthesisComplete', () {
      test('updates avgRtf', () {
        final strategy = AdaptiveSynthesisStrategy();
        
        strategy.onSynthesisComplete(
          segmentIndex: 0,
          synthesisTime: const Duration(milliseconds: 500),
          audioDuration: const Duration(milliseconds: 1000),
        );
        
        // RTF = 500/1000 = 0.5
        // Average = (0.5 * 0 + 0.5) / 1 = 0.5
        expect(strategy.avgRtf, 0.5);
        expect(strategy.completedCount, 1);
      });

      test('adjusts preSynthesizeCount after 5 completions for fast RTF', () {
        final strategy = AdaptiveSynthesisStrategy();
        
        // Simulate 5 fast synthesis operations (RTF = 0.2)
        for (int i = 0; i < 5; i++) {
          strategy.onSynthesisComplete(
            segmentIndex: i,
            synthesisTime: const Duration(milliseconds: 200),
            audioDuration: const Duration(milliseconds: 1000),
          );
        }
        
        // With avgRtf < 0.3, should increase to 5
        expect(strategy.preSynthesizeCount, 5);
      });

      test('adjusts preSynthesizeCount after 5 completions for slow RTF', () {
        final strategy = AdaptiveSynthesisStrategy();
        
        // Simulate 5 slow synthesis operations (RTF = 0.9)
        for (int i = 0; i < 5; i++) {
          strategy.onSynthesisComplete(
            segmentIndex: i,
            synthesisTime: const Duration(milliseconds: 900),
            audioDuration: const Duration(milliseconds: 1000),
          );
        }
        
        // With avgRtf > 0.8, should decrease to 2
        expect(strategy.preSynthesizeCount, 2);
      });

      test('ignores synthesis with zero audio duration', () {
        final strategy = AdaptiveSynthesisStrategy();
        
        strategy.onSynthesisComplete(
          segmentIndex: 0,
          synthesisTime: const Duration(milliseconds: 500),
          audioDuration: Duration.zero,
        );
        
        expect(strategy.completedCount, 0);
        expect(strategy.avgRtf, 0.5); // Unchanged
      });
    });
  });

  group('AggressiveSynthesisStrategy', () {
    test('has aggressive defaults', () {
      const strategy = AggressiveSynthesisStrategy();
      expect(strategy.preSynthesizeCount, 10);
      expect(strategy.maxConcurrency, 2);
      expect(strategy.name, 'Aggressive');
    });

    test('serializes and deserializes', () {
      const strategy = AggressiveSynthesisStrategy();
      final json = strategy.toJson();
      expect(json['type'], 'aggressive');
      
      final restored = AggressiveSynthesisStrategy.fromJson(json);
      expect(restored, isA<AggressiveSynthesisStrategy>());
    });

    group('shouldContinuePrefetch', () {
      test('returns true when remaining segments exist and buffer is below 5 min', () {
        const strategy = AggressiveSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 200000, // 200 seconds
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, true);
      });

      test('returns false when buffer is 5 minutes', () {
        const strategy = AggressiveSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 300000, // 5 minutes
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, false);
      });

      test('returns false when no remaining segments', () {
        const strategy = AggressiveSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 100000,
          remainingSegments: 0,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, false);
      });

      test('continues prefetching even when not playing', () {
        const strategy = AggressiveSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 100000,
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: false,
        );
        expect(result, true);
      });
    });
  });

  group('ConservativeSynthesisStrategy', () {
    test('has conservative defaults', () {
      const strategy = ConservativeSynthesisStrategy();
      expect(strategy.preSynthesizeCount, 1);
      expect(strategy.maxConcurrency, 1);
      expect(strategy.name, 'Conservative');
    });

    test('serializes and deserializes', () {
      const strategy = ConservativeSynthesisStrategy();
      final json = strategy.toJson();
      expect(json['type'], 'conservative');
      
      final restored = ConservativeSynthesisStrategy.fromJson(json);
      expect(restored, isA<ConservativeSynthesisStrategy>());
    });

    group('shouldContinuePrefetch', () {
      test('returns true only when playing and buffer is very low', () {
        const strategy = ConservativeSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 10000, // 10 seconds
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, true);
      });

      test('returns false when not playing', () {
        const strategy = ConservativeSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 10000,
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: false,
        );
        expect(result, false);
      });

      test('returns false when buffer is above 15 seconds', () {
        const strategy = ConservativeSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 20000, // 20 seconds
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, false);
      });

      test('returns false when no remaining segments', () {
        const strategy = ConservativeSynthesisStrategy();
        final result = strategy.shouldContinuePrefetch(
          bufferedMs: 10000,
          remainingSegments: 0,
          recentRtf: 0.5,
          isPlaying: true,
        );
        expect(result, false);
      });
    });
  });

  group('SynthesisStrategyType', () {
    test('displayName returns correct strings', () {
      expect(SynthesisStrategyType.adaptive.displayName, 'Adaptive');
      expect(SynthesisStrategyType.aggressive.displayName, 'Aggressive');
      expect(SynthesisStrategyType.conservative.displayName, 'Conservative');
    });

    test('description returns non-empty strings', () {
      expect(SynthesisStrategyType.adaptive.description, isNotEmpty);
      expect(SynthesisStrategyType.aggressive.description, isNotEmpty);
      expect(SynthesisStrategyType.conservative.description, isNotEmpty);
    });
  });
}
