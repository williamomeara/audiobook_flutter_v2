import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/src/adapters/routing_engine.dart';
import 'package:tts_engines/src/cache/audio_cache.dart';
import 'package:tts_engines/src/interfaces/ai_voice_engine.dart';
import 'package:tts_engines/src/interfaces/tts_state_machines.dart';

/// Mock AudioCache for testing
class MockAudioCache implements AudioCache {
  @override
  Future<bool> isReady(CacheKey key) async => false;
  
  @override
  Future<File> fileFor(CacheKey key) async => File('/tmp/mock.wav');
  
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Mock AiVoiceEngine for testing
class MockVoiceEngine implements AiVoiceEngine {
  final String name;
  final Map<String, StreamController<CoreReadiness>> _controllers = {};
  bool disposed = false;
  
  MockVoiceEngine(this.name);
  
  @override
  EngineType get engineType => EngineType.device;
  
  @override
  Stream<CoreReadiness> watchCoreReadiness(String coreId) {
    _controllers[coreId] ??= StreamController<CoreReadiness>.broadcast();
    return _controllers[coreId]!.stream;
  }
  
  /// Emit a readiness event for a coreId
  void emitReadiness(String coreId, CoreReadiness readiness) {
    _controllers[coreId]?.add(readiness);
  }
  
  @override
  Future<void> dispose() async {
    disposed = true;
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('RoutingEngine readiness controller management', () {
    late RoutingEngine routingEngine;
    late MockAudioCache mockCache;
    late MockVoiceEngine mockKokoro;
    late MockVoiceEngine mockPiper;
    
    setUp(() {
      mockCache = MockAudioCache();
      mockKokoro = MockVoiceEngine('kokoro');
      mockPiper = MockVoiceEngine('piper');
      
      routingEngine = RoutingEngine(
        cache: mockCache,
        kokoroEngine: mockKokoro,
        piperEngine: mockPiper,
      );
    });
    
    tearDown(() async {
      await routingEngine.dispose();
    });
    
    test('watchCoreReadiness reuses controller for same coreId', () async {
      // Subscribe to same coreId twice
      final events1 = <CoreReadiness>[];
      final events2 = <CoreReadiness>[];
      
      final sub1 = routingEngine.watchCoreReadiness('core1').listen(events1.add);
      final sub2 = routingEngine.watchCoreReadiness('core1').listen(events2.add);
      
      // Emit one event - both listeners should receive it
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(events1.length, equals(1));
      expect(events2.length, equals(1));
      
      await sub1.cancel();
      await sub2.cancel();
    });
    
    test('watchCoreReadiness creates separate controllers for different coreIds', () async {
      final events1 = <CoreReadiness>[];
      final events2 = <CoreReadiness>[];
      
      final sub1 = routingEngine.watchCoreReadiness('core1').listen(events1.add);
      final sub2 = routingEngine.watchCoreReadiness('core2').listen(events2.add);
      
      // Emit to core1 only
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(events1.length, equals(1));
      expect(events2.length, equals(0)); // core2 should not receive core1 events
      
      await sub1.cancel();
      await sub2.cancel();
    });
    
    test('controller cleanup happens when all listeners unsubscribe', () async {
      final events1 = <CoreReadiness>[];
      final events2 = <CoreReadiness>[];
      
      // Create two subscriptions
      final sub1 = routingEngine.watchCoreReadiness('core1').listen(events1.add);
      final sub2 = routingEngine.watchCoreReadiness('core1').listen(events2.add);
      
      // Emit initial event - both receive it
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      expect(events1.length, equals(1));
      expect(events2.length, equals(1));
      
      // Cancel first - controller should remain
      await sub1.cancel();
      
      // Emit again - sub2 still receives
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      expect(events2.length, equals(2));
      
      // Cancel second - controller should be cleaned up
      await sub2.cancel();
      await Future.delayed(Duration(milliseconds: 10));
      
      // Create new subscription - should create fresh controller
      final events3 = <CoreReadiness>[];
      final sub3 = routingEngine.watchCoreReadiness('core1').listen(events3.add);
      
      // Emit - new subscription should work
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      expect(events3.length, equals(1));
      
      await sub3.cancel();
    });
    
    test('dispose cleans up all controllers and disposes child engines', () async {
      // Create subscriptions to multiple coreIds
      final sub1 = routingEngine.watchCoreReadiness('core1').listen((_) {});
      final sub2 = routingEngine.watchCoreReadiness('core2').listen((_) {});
      final sub3 = routingEngine.watchCoreReadiness('core3').listen((_) {});
      
      // Dispose should not throw
      await routingEngine.dispose();
      
      // Underlying engines should be disposed
      expect(mockKokoro.disposed, isTrue);
      expect(mockPiper.disposed, isTrue);
      
      // Cancel subscriptions (already disposed but shouldn't throw)
      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
    });
    
    test('readiness events are forwarded from child engines', () async {
      final events = <CoreReadiness>[];
      final sub = routingEngine.watchCoreReadiness('core1').listen(events.add);
      
      // Emit from kokoro
      final readiness1 = CoreReadiness.readyFor('core1');
      mockKokoro.emitReadiness('core1', readiness1);
      
      // Small delay for event propagation
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(events.length, equals(1));
      expect(events[0].isReady, isTrue);
      
      await sub.cancel();
    });
    
    test('multiple coreIds can be watched simultaneously', () async {
      final events1 = <CoreReadiness>[];
      final events2 = <CoreReadiness>[];
      
      final sub1 = routingEngine.watchCoreReadiness('core1').listen(events1.add);
      final sub2 = routingEngine.watchCoreReadiness('core2').listen(events2.add);
      
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      mockKokoro.emitReadiness('core2', CoreReadiness.readyFor('core2'));
      
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(events1.length, equals(1));
      expect(events2.length, equals(1));
      
      await sub1.cancel();
      await sub2.cancel();
    });
    
    test('listener count is tracked correctly across subscribe/unsubscribe', () async {
      final events = <int>[];
      
      // Add 3 listeners
      final sub1 = routingEngine.watchCoreReadiness('core1').listen((_) => events.add(1));
      final sub2 = routingEngine.watchCoreReadiness('core1').listen((_) => events.add(2));
      final sub3 = routingEngine.watchCoreReadiness('core1').listen((_) => events.add(3));
      
      // Emit - all 3 should receive
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      expect(events.length, equals(3));
      
      // Cancel 2 listeners
      await sub2.cancel();
      await sub1.cancel();
      events.clear();
      
      // Emit - only sub3 should receive
      mockKokoro.emitReadiness('core1', CoreReadiness.readyFor('core1'));
      await Future.delayed(Duration(milliseconds: 10));
      expect(events.length, equals(1));
      expect(events[0], equals(3));
      
      // Cancel last
      await sub3.cancel();
    });
  });
}
