import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

void main() {
  group('SynthesisStrategyManager', () {
    test('initializes with AdaptiveSynthesisStrategy by default', () {
      final manager = SynthesisStrategyManager();
      expect(manager.strategy, isA<AdaptiveSynthesisStrategy>());
      expect(manager.strategyType, SynthesisStrategyType.adaptive);
    });

    test('initializes with provided strategy', () {
      final manager = SynthesisStrategyManager(
        strategy: const AggressiveSynthesisStrategy(),
      );
      expect(manager.strategy, isA<AggressiveSynthesisStrategy>());
      expect(manager.strategyType, SynthesisStrategyType.aggressive);
    });

    group('setStrategy', () {
      test('changes strategy', () {
        final manager = SynthesisStrategyManager();
        manager.setStrategy(const AggressiveSynthesisStrategy());
        expect(manager.strategy, isA<AggressiveSynthesisStrategy>());
      });

      test('calls onStrategyChanged callback when type changes', () {
        final manager = SynthesisStrategyManager();
        SynthesisStrategy? changedTo;
        manager.setOnStrategyChanged((s) => changedTo = s);

        manager.setStrategy(const AggressiveSynthesisStrategy());

        expect(changedTo, isA<AggressiveSynthesisStrategy>());
      });

      test('does not call callback when setting same type', () {
        final manager = SynthesisStrategyManager(
          strategy: const AggressiveSynthesisStrategy(),
        );
        var callCount = 0;
        manager.setOnStrategyChanged((_) => callCount++);

        manager.setStrategy(const AggressiveSynthesisStrategy());

        expect(callCount, 0);
      });
    });

    group('setStrategyType', () {
      test('changes strategy by type', () {
        final manager = SynthesisStrategyManager();
        manager.setStrategyType(SynthesisStrategyType.conservative);
        expect(manager.strategy, isA<ConservativeSynthesisStrategy>());
        expect(manager.strategyType, SynthesisStrategyType.conservative);
      });
    });

    group('autoSelectStrategy', () {
      test('selects conservative when in low power mode', () {
        final manager = SynthesisStrategyManager();
        manager.autoSelectStrategy(
          isCharging: true,
          isLowPowerMode: true,
          measuredRtf: 0.2,
        );
        expect(manager.strategy, isA<ConservativeSynthesisStrategy>());
      });

      test('selects aggressive when charging with fast RTF', () {
        final manager = SynthesisStrategyManager();
        manager.autoSelectStrategy(
          isCharging: true,
          isLowPowerMode: false,
          measuredRtf: 0.3,
        );
        expect(manager.strategy, isA<AggressiveSynthesisStrategy>());
      });

      test('selects adaptive by default', () {
        final manager = SynthesisStrategyManager(
          strategy: const AggressiveSynthesisStrategy(),
        );
        manager.autoSelectStrategy(
          isCharging: false,
          isLowPowerMode: false,
          measuredRtf: 0.5,
        );
        expect(manager.strategy, isA<AdaptiveSynthesisStrategy>());
      });

      test('preserves adaptive if already adaptive', () {
        final adaptive = AdaptiveSynthesisStrategy(
          preSynthesizeCount: 5,
          avgRtf: 0.3,
          completedCount: 10,
        );
        final manager = SynthesisStrategyManager(strategy: adaptive);

        manager.autoSelectStrategy(
          isCharging: false,
          isLowPowerMode: false,
          measuredRtf: 0.5,
        );

        // Should be the same instance with preserved learned values
        expect(manager.strategy, same(adaptive));
        expect((manager.strategy as AdaptiveSynthesisStrategy).avgRtf, 0.3);
      });
    });

    group('shouldContinuePrefetch delegation', () {
      test('delegates to current strategy', () {
        final manager = SynthesisStrategyManager(
          strategy: const ConservativeSynthesisStrategy(),
        );

        // Conservative returns false when not playing
        final result = manager.shouldContinuePrefetch(
          bufferedMs: 10000,
          remainingSegments: 10,
          recentRtf: 0.5,
          isPlaying: false,
        );

        expect(result, false);
      });
    });

    group('onSynthesisComplete delegation', () {
      test('delegates to current strategy', () {
        final adaptive = AdaptiveSynthesisStrategy();
        final manager = SynthesisStrategyManager(strategy: adaptive);

        manager.onSynthesisComplete(
          segmentIndex: 0,
          synthesisTime: const Duration(milliseconds: 500),
          audioDuration: const Duration(milliseconds: 1000),
        );

        expect(adaptive.completedCount, 1);
      });
    });

    group('serialization', () {
      test('toJson returns strategy JSON', () {
        final manager = SynthesisStrategyManager(
          strategy: const AggressiveSynthesisStrategy(),
        );
        final json = manager.toJson();
        expect(json['type'], 'aggressive');
      });

      test('fromJson creates manager with correct strategy', () {
        final json = {'type': 'conservative'};
        final manager = SynthesisStrategyManager.fromJson(json);
        expect(manager.strategy, isA<ConservativeSynthesisStrategy>());
      });

      test('round-trip preserves adaptive strategy state', () {
        final original = SynthesisStrategyManager(
          strategy: AdaptiveSynthesisStrategy(
            preSynthesizeCount: 5,
            avgRtf: 0.25,
            completedCount: 10,
          ),
        );

        final json = original.toJson();
        final restored = SynthesisStrategyManager.fromJson(json);

        final strategy = restored.strategy as AdaptiveSynthesisStrategy;
        expect(strategy.preSynthesizeCount, 5);
        expect(strategy.avgRtf, 0.25);
        expect(strategy.completedCount, 10);
      });
    });
  });
}
