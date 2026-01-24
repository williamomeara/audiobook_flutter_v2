import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/adaptive_prefetch.dart';
import 'package:playback/src/edge_cases/memory_pressure_handler.dart';

void main() {
  group('MemoryPressureHandler', () {
    late MemoryPressureHandler handler;
    late List<MemoryPressure> reducePrefetchCalls;
    late List<MemoryPressure> pauseSynthesisCalls;
    late List<MemoryPressure> trimCacheCalls;
    late List<MemoryPressure> resumeSynthesisCalls;

    setUp(() {
      reducePrefetchCalls = [];
      pauseSynthesisCalls = [];
      trimCacheCalls = [];
      resumeSynthesisCalls = [];

      handler = MemoryPressureHandler(
        onReducePrefetch: (level) async => reducePrefetchCalls.add(level),
        onPauseSynthesis: (level) async => pauseSynthesisCalls.add(level),
        onTrimCache: (level) async => trimCacheCalls.add(level),
        onResumeSynthesis: (level) async => resumeSynthesisCalls.add(level),
        recoveryDelay: const Duration(seconds: 5),
      );
    });

    test('initial state is none', () {
      expect(handler.currentPressure, MemoryPressure.none);
      expect(handler.isSynthesisPaused, false);
      expect(handler.canStartSynthesis(), true);
    });

    test('moderate pressure reduces prefetch and trims cache', () async {
      await handler.handlePressure(MemoryPressure.moderate);

      expect(handler.currentPressure, MemoryPressure.moderate);
      expect(reducePrefetchCalls, [MemoryPressure.moderate]);
      expect(trimCacheCalls, [MemoryPressure.moderate]);
      expect(pauseSynthesisCalls, isEmpty);
      expect(handler.canStartSynthesis(), true);
    });

    test('critical pressure pauses synthesis', () async {
      await handler.handlePressure(MemoryPressure.critical);

      expect(handler.currentPressure, MemoryPressure.critical);
      expect(handler.isSynthesisPaused, true);
      expect(handler.canStartSynthesis(), false);
      expect(pauseSynthesisCalls, [MemoryPressure.critical]);
      expect(reducePrefetchCalls, [MemoryPressure.critical]);
      expect(trimCacheCalls, [MemoryPressure.critical]);
    });

    test('returning to none resumes synthesis', () async {
      await handler.handlePressure(MemoryPressure.critical);
      expect(handler.isSynthesisPaused, true);

      await handler.handlePressure(MemoryPressure.none);

      expect(handler.currentPressure, MemoryPressure.none);
      expect(handler.isSynthesisPaused, false);
      expect(resumeSynthesisCalls, [MemoryPressure.none]);
    });

    test('multiple critical calls do not re-pause', () async {
      await handler.handlePressure(MemoryPressure.critical);
      await handler.handlePressure(MemoryPressure.critical);
      await handler.handlePressure(MemoryPressure.critical);

      // Pause should only be called once
      expect(pauseSynthesisCalls.length, 1);
    });

    test('recovery timer resumes after moderate pressure', () {
      fakeAsync((async) {
        handler.handlePressure(MemoryPressure.critical);
        
        // Move to moderate
        handler.handlePressure(MemoryPressure.moderate);
        
        // Synthesis still paused
        expect(handler.isSynthesisPaused, true);
        
        // Advance past recovery delay
        async.elapse(const Duration(seconds: 6));
        
        // Should have resumed
        expect(handler.isSynthesisPaused, false);
        expect(resumeSynthesisCalls, isNotEmpty);
      });
    });

    test('recovery timer is cancelled on new pressure event', () {
      fakeAsync((async) {
        handler.handlePressure(MemoryPressure.critical);
        handler.handlePressure(MemoryPressure.moderate);
        
        // Before recovery
        async.elapse(const Duration(seconds: 2));
        
        // New critical pressure
        handler.handlePressure(MemoryPressure.critical);
        
        // Advance past original recovery time
        async.elapse(const Duration(seconds: 4));
        
        // Should still be paused
        expect(handler.isSynthesisPaused, true);
      });
    });

    test('timeSinceLastPressure tracks correctly', () async {
      expect(handler.timeSinceLastPressure, null);

      await handler.handlePressure(MemoryPressure.moderate);
      
      // Should be very recent
      expect(handler.timeSinceLastPressure!.inMilliseconds, lessThan(100));
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      expect(handler.timeSinceLastPressure!.inMilliseconds, greaterThan(40));
    });

    test('requestCacheTrim calls trim handler', () async {
      await handler.requestCacheTrim();

      expect(trimCacheCalls, [MemoryPressure.none]);
    });

    test('dispose cleans up resources', () {
      handler.dispose();
      // Should not throw
    });
  });
}
