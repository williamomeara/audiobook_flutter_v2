import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/edge_cases/rate_change_handler.dart';

void main() {
  group('RateChangeHandler', () {
    late RateChangeHandler handler;
    late List<double> stabilizedRates;
    late List<String> cancelReasons;
    late int prefetchRestarts;

    setUp(() {
      stabilizedRates = [];
      cancelReasons = [];
      prefetchRestarts = 0;

      handler = RateChangeHandler(
        onRateStabilized: (rate) => stabilizedRates.add(rate),
        onCancelPrefetch: (reason) => cancelReasons.add(reason),
        onRestartPrefetch: () async => prefetchRestarts++,
        debounceDelay: const Duration(milliseconds: 500),
        rateIndependentSynthesis: true,
      );
    });

    test('setInitialRate sets rate without handlers', () {
      handler.setInitialRate(1.5);

      expect(handler.currentRate, 1.5);
      expect(stabilizedRates, isEmpty);
      expect(cancelReasons, isEmpty);
    });

    test('handleRateChange debounces rapid changes', () {
      fakeAsync((async) {
        handler.handleRateChange(1.1);
        handler.handleRateChange(1.2);
        handler.handleRateChange(1.3);

        // Before debounce completes
        expect(handler.isDebouncing, true);
        expect(stabilizedRates, isEmpty);

        // Advance past debounce
        async.elapse(const Duration(milliseconds: 600));

        // Only final rate should be applied
        expect(stabilizedRates, [1.3]);
        expect(handler.currentRate, 1.3);
        expect(handler.isDebouncing, false);
      });
    });

    test('handleRateChange cancels prefetch on significant change', () {
      handler.setInitialRate(1.0);
      handler.handleRateChange(1.5); // 0.5 difference > 0.25 threshold

      expect(cancelReasons.length, 1);
      expect(cancelReasons.first, contains('rate change'));
    });

    test('handleRateChange clamps rate to valid range', () {
      fakeAsync((async) {
        handler.handleRateChange(5.0); // Above max 3.0
        async.elapse(const Duration(milliseconds: 600));

        expect(handler.currentRate, 3.0);
        expect(stabilizedRates, [3.0]);
      });
    });

    test('applyImmediately skips debounce', () async {
      handler.handleRateChange(1.5);
      expect(handler.isDebouncing, true);

      await handler.applyImmediately();

      expect(handler.isDebouncing, false);
      expect(stabilizedRates, [1.5]);
    });

    test('cancel removes pending rate change', () {
      fakeAsync((async) {
        handler.setInitialRate(1.0);
        handler.handleRateChange(1.5);
        expect(handler.isDebouncing, true);

        handler.cancel();

        expect(handler.isDebouncing, false);
        
        // Advance time - nothing should happen
        async.elapse(const Duration(milliseconds: 600));
        expect(stabilizedRates, isEmpty);
        expect(handler.currentRate, 1.0); // Still original
      });
    });

    test('tracks pending change count', () {
      handler.handleRateChange(1.1);
      handler.handleRateChange(1.2);
      handler.handleRateChange(1.3);

      expect(handler.pendingChangeCount, 3);
    });

    test('rate-dependent mode triggers re-synthesis', () async {
      final dependentHandler = RateChangeHandler(
        onRateStabilized: (rate) => stabilizedRates.add(rate),
        onCancelPrefetch: (reason) => cancelReasons.add(reason),
        onRestartPrefetch: () async => prefetchRestarts++,
        debounceDelay: Duration.zero, // No debounce for test
        rateIndependentSynthesis: false, // Rate-dependent
      );

      dependentHandler.handleRateChange(1.5);
      await Future.delayed(const Duration(milliseconds: 10));

      // Should cancel for re-synthesis
      expect(
        cancelReasons.any((r) => r.contains('re-synthesis')),
        true,
      );
    });

    test('dispose cleans up timer', () {
      handler.handleRateChange(1.5);
      expect(handler.isDebouncing, true);

      handler.dispose();

      // Timer should be cancelled (no way to verify directly, but no exception)
      expect(handler.isDebouncing, false);
    });
  });
}
