import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

void main() {
  group('CalibrationResult', () {
    test('stores all fields correctly', () {
      final result = CalibrationResult(
        optimalConcurrency: 3,
        expectedSpeedup: 1.65,
        rtfAtOptimal: 2.1,
        hasWarnings: false,
        calibrationDurationMs: 30000,
        testResults: {
          1: ConcurrencyTestResult(
            concurrency: 1,
            totalTimeMs: 10000,
            segmentsCompleted: 3,
            segmentsFailed: 0,
            audioDurationSeconds: 5.0,
            rtf: 2.0,
          ),
          2: ConcurrencyTestResult(
            concurrency: 2,
            totalTimeMs: 6500,
            segmentsCompleted: 3,
            segmentsFailed: 0,
            audioDurationSeconds: 5.0,
            rtf: 1.3,
          ),
          3: ConcurrencyTestResult(
            concurrency: 3,
            totalTimeMs: 6000,
            segmentsCompleted: 3,
            segmentsFailed: 0,
            audioDurationSeconds: 5.0,
            rtf: 1.2,
          ),
        },
      );

      expect(result.optimalConcurrency, 3);
      expect(result.expectedSpeedup, 1.65);
      expect(result.rtfAtOptimal, 2.1);
      expect(result.hasWarnings, false);
      expect(result.calibrationDurationMs, 30000);
      expect(result.testResults.length, 3);
    });

    test('toString provides useful information', () {
      final result = CalibrationResult(
        optimalConcurrency: 2,
        expectedSpeedup: 1.48,
        rtfAtOptimal: 2.5,
        hasWarnings: false,
        calibrationDurationMs: 25000,
        testResults: {},
      );

      expect(result.toString(), contains('optimal=2'));
      expect(result.toString(), contains('speedup=1.48'));
      expect(result.toString(), contains('rtf=2.50'));
    });
  });

  group('ConcurrencyTestResult', () {
    test('calculates failure rate correctly', () {
      final resultNoFailures = ConcurrencyTestResult(
        concurrency: 2,
        totalTimeMs: 5000,
        segmentsCompleted: 10,
        segmentsFailed: 0,
        audioDurationSeconds: 10.0,
        rtf: 0.5,
      );

      expect(resultNoFailures.failureRate, 0.0);

      final resultWithFailures = ConcurrencyTestResult(
        concurrency: 3,
        totalTimeMs: 4000,
        segmentsCompleted: 8,
        segmentsFailed: 2,
        audioDurationSeconds: 8.0,
        rtf: 0.5,
      );

      expect(resultWithFailures.failureRate, 0.2); // 2 out of 10 = 20%
    });

    test('handles zero segments gracefully', () {
      final result = ConcurrencyTestResult(
        concurrency: 1,
        totalTimeMs: 0,
        segmentsCompleted: 0,
        segmentsFailed: 0,
        audioDurationSeconds: 0,
        rtf: 0,
      );

      expect(result.failureRate, 0.0);
    });
  });

  group('EngineCalibrationService', () {
    test('can be instantiated', () {
      final service = EngineCalibrationService();
      expect(service, isNotNull);
    });
  });
}
