import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/edge_cases/auto_tune_rollback.dart';
import 'package:playback/src/edge_cases/config_snapshot.dart';

void main() {
  group('AutoTuneRollback', () {
    late AutoTuneRollback rollback;

    setUp(() {
      rollback = AutoTuneRollback();
    });

    test('saveSnapshot adds to snapshots list', () {
      final snapshot = ConfigSnapshot(
        prefetchConcurrency: 2,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'test snapshot',
      );

      rollback.saveSnapshot(snapshot);

      expect(rollback.snapshots.length, 1);
      expect(rollback.latestSnapshot, snapshot);
    });

    test('saveSnapshot limits to maxSnapshots', () {
      for (var i = 0; i < 10; i++) {
        rollback.saveSnapshot(ConfigSnapshot(
          prefetchConcurrency: i,
          parallelSynthesisEnabled: true,
          bufferTargetMs: 30000,
          timestamp: DateTime.now(),
          reason: 'snapshot $i',
        ));
      }

      // Default maxSnapshots is 5
      expect(rollback.snapshots.length, 5);
      // Should have the latest 5 (5-9)
      expect(rollback.snapshots.first.prefetchConcurrency, 5);
      expect(rollback.latestSnapshot?.prefetchConcurrency, 9);
    });

    test('checkForRollback returns no rollback when metrics are good', () {
      rollback.saveSnapshot(ConfigSnapshot(
        prefetchConcurrency: 2,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'baseline',
      ));

      final metrics = PerformanceMetrics(
        bufferUnderrunCount: 1,
        synthesisFailureCount: 0,
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 60000,
      );

      final decision = rollback.checkForRollback(metrics);
      expect(decision.needsRollback, false);
    });

    test('checkForRollback triggers on high failure rate', () {
      rollback.saveSnapshot(ConfigSnapshot(
        prefetchConcurrency: 2,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'baseline',
      ));

      // High failure rate (>10%)
      final metrics = PerformanceMetrics(
        bufferUnderrunCount: 0,
        synthesisFailureCount: 100, // Many failures
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 60000, // 600 estimated syntheses = 16.7% failure
      );

      final decision = rollback.checkForRollback(metrics);
      expect(decision.needsRollback, true);
      expect(decision.reason, contains('failure'));
    });

    test('checkForRollback triggers on underrun rate increase', () {
      // Set baseline
      rollback.setBaseline(PerformanceMetrics(
        bufferUnderrunCount: 2,
        synthesisFailureCount: 0,
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 3600000, // 1 hour = 2/hr baseline
      ));

      rollback.saveSnapshot(ConfigSnapshot(
        prefetchConcurrency: 2,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'baseline',
      ));

      // 50%+ increase: 4/hr > 2/hr * 1.5 = 3/hr
      final metrics = PerformanceMetrics(
        bufferUnderrunCount: 4,
        synthesisFailureCount: 0,
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 3600000, // 1 hour = 4/hr
      );

      final decision = rollback.checkForRollback(metrics);
      expect(decision.needsRollback, true);
      expect(decision.reason, contains('underrun'));
    });

    test('forceRollback returns and removes latest snapshot', () {
      final snapshot1 = ConfigSnapshot(
        prefetchConcurrency: 1,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'first',
      );
      final snapshot2 = ConfigSnapshot(
        prefetchConcurrency: 2,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'second',
      );

      rollback.saveSnapshot(snapshot1);
      rollback.saveSnapshot(snapshot2);

      expect(rollback.snapshots.length, 2);

      final result = rollback.forceRollback(reason: 'user request');

      expect(result, snapshot2);
      expect(rollback.snapshots.length, 1);
      expect(rollback.latestSnapshot, snapshot1);
    });

    test('forceRollback returns null when no snapshots', () {
      final result = rollback.forceRollback();
      expect(result, null);
    });

    test('clearSnapshots removes all snapshots', () {
      rollback.saveSnapshot(ConfigSnapshot(
        prefetchConcurrency: 2,
        parallelSynthesisEnabled: true,
        bufferTargetMs: 30000,
        timestamp: DateTime.now(),
        reason: 'test',
      ));

      rollback.clearSnapshots();

      expect(rollback.snapshots, isEmpty);
    });

    test('toJson and fromJson roundtrip', () {
      rollback.saveSnapshot(ConfigSnapshot(
        prefetchConcurrency: 3,
        parallelSynthesisEnabled: false,
        bufferTargetMs: 45000,
        timestamp: DateTime(2024, 1, 1, 12, 0),
        reason: 'serialization test',
      ));

      final json = rollback.toJson();
      
      final newRollback = AutoTuneRollback();
      newRollback.fromJson(json);

      expect(newRollback.snapshots.length, 1);
      expect(newRollback.latestSnapshot?.prefetchConcurrency, 3);
      expect(newRollback.latestSnapshot?.parallelSynthesisEnabled, false);
      expect(newRollback.latestSnapshot?.bufferTargetMs, 45000);
      expect(newRollback.latestSnapshot?.reason, 'serialization test');
    });
  });

  group('PerformanceMetrics', () {
    test('bufferUnderrunRate calculates correctly', () {
      final metrics = PerformanceMetrics(
        bufferUnderrunCount: 6,
        synthesisFailureCount: 0,
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 3600000, // 1 hour
      );

      expect(metrics.bufferUnderrunRate, 6.0); // 6 per hour
    });

    test('bufferUnderrunRate handles zero period', () {
      final metrics = PerformanceMetrics(
        bufferUnderrunCount: 6,
        synthesisFailureCount: 0,
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 0,
      );

      expect(metrics.bufferUnderrunRate, 0.0);
    });

    test('synthesisFailureRate calculates correctly', () {
      final metrics = PerformanceMetrics(
        bufferUnderrunCount: 0,
        synthesisFailureCount: 10,
        avgSynthesisTimeMs: 100,
        measurementPeriodMs: 10000, // 100 estimated syntheses
      );

      expect(metrics.synthesisFailureRate, closeTo(0.1, 0.001)); // 10%
    });
  });
}
