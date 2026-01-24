import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

void main() {
  group('PrefetchResumeController', () {
    late PrefetchResumeController controller;

    setUp(() {
      controller = PrefetchResumeController(resumeDelayMs: 500);
    });

    tearDown(() {
      controller.dispose();
    });

    group('suspend and resume', () {
      test('isSuspended should be false initially', () {
        expect(controller.isSuspended, false);
      });

      test('suspend should set isSuspended to true', () {
        controller.suspend();

        expect(controller.isSuspended, true);
      });

      test('suspend should call onResume callback after delay', () async {
        var resumed = false;
        controller.setOnResume(() => resumed = true);

        controller.suspend();
        expect(controller.isSuspended, true);
        expect(resumed, false);

        // Wait for delay + buffer
        await Future.delayed(const Duration(milliseconds: 600));

        expect(controller.isSuspended, false);
        expect(resumed, true);
      });

      test('resumeImmediately should bypass timer', () async {
        var resumed = false;
        controller.setOnResume(() => resumed = true);

        controller.suspend();
        expect(controller.isSuspended, true);

        controller.resumeImmediately();
        expect(controller.isSuspended, false);
        expect(resumed, true);
      });

      test('resumeImmediately should work even if not suspended', () {
        var resumeCount = 0;
        controller.setOnResume(() => resumeCount++);

        // Not suspended, resumeImmediately should be safe
        controller.resumeImmediately();
        
        // Should not call callback since not suspended
        expect(resumeCount, 0);
      });

      test('cancel should prevent resume callback', () async {
        var resumed = false;
        controller.setOnResume(() => resumed = true);

        controller.suspend();
        controller.cancel();

        // Wait for delay + buffer
        await Future.delayed(const Duration(milliseconds: 600));

        // Should still be suspended because we cancelled
        expect(resumed, false);
      });
    });

    group('rapid seek detection', () {
      test('effectiveDelay should be base delay normally', () {
        expect(controller.effectiveDelay.inMilliseconds, 500);
      });

      test('effectiveDelay should double after 3+ rapid seeks', () async {
        // Simulate 3 rapid seeks
        controller.suspend();
        await Future.delayed(const Duration(milliseconds: 50));
        controller.suspend();
        await Future.delayed(const Duration(milliseconds: 50));
        controller.suspend();

        // After 3 seeks in quick succession, delay should double
        expect(controller.effectiveDelay.inMilliseconds, 1000);
      });

      test('seek count should reset after resume', () async {
        var resumed = false;
        controller.setOnResume(() => resumed = true);

        // Simulate 3 rapid seeks
        controller.suspend();
        await Future.delayed(const Duration(milliseconds: 50));
        controller.suspend();
        await Future.delayed(const Duration(milliseconds: 50));
        controller.suspend();

        expect(controller.effectiveDelay.inMilliseconds, 1000);

        // Wait for resume
        await Future.delayed(const Duration(milliseconds: 1100));

        expect(resumed, true);

        // After resume, new seeks should start fresh
        controller.suspend();
        expect(controller.effectiveDelay.inMilliseconds, 500);
      });

      test('slow seeks should not trigger doubled delay', () async {
        // Simulate seeks more than 2 seconds apart
        controller.suspend();
        await Future.delayed(const Duration(milliseconds: 2100));
        controller.suspend();

        // Not rapid enough - should be base delay
        expect(controller.effectiveDelay.inMilliseconds, 500);
      });
    });

    group('dispose', () {
      test('dispose should cancel pending timer', () async {
        var resumed = false;
        controller.setOnResume(() => resumed = true);

        controller.suspend();
        controller.dispose();

        // Wait for what would have been the delay
        await Future.delayed(const Duration(milliseconds: 600));

        expect(resumed, false);
      });
    });
  });
}
