import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/src/buffer_scheduler.dart';
import 'package:tts_engines/tts_engines.dart';

/// Mock RoutingEngine for testing
class MockRoutingEngine implements RoutingEngine {
  final Duration synthesisDelay;
  int synthesizeCalls = 0;
  List<int> synthesizedSegments = [];
  
  MockRoutingEngine({this.synthesisDelay = const Duration(milliseconds: 10)});
  
  @override
  Future<SynthResult> synthesizeToWavFile({
    required String voiceId,
    required String text,
    required double playbackRate,
  }) async {
    synthesizeCalls++;
    await Future.delayed(synthesisDelay);
    return SynthResult(
      file: File('/fake/path.wav'),
      durationMs: 1000,
    );
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Mock AudioCache for testing
class MockAudioCache implements AudioCache {
  final Set<CacheKey> _readyKeys = {};
  
  void setReady(CacheKey key) => _readyKeys.add(key);
  
  @override
  Future<void> clear() async => _readyKeys.clear();
  
  @override
  Future<bool> isReady(CacheKey key) async => _readyKeys.contains(key);
  
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

List<AudioTrack> createTestQueue(int count) {
  return List.generate(count, (i) => AudioTrack(
    id: 'track_$i',
    text: 'This is test text for segment $i with some words.',
    chapterIndex: 0,
    segmentIndex: i,
  ));
}

void main() {
  group('BufferScheduler', () {
    late BufferScheduler scheduler;
    late MockRoutingEngine engine;
    late MockAudioCache cache;
    late List<AudioTrack> queue;
    
    setUp(() {
      scheduler = BufferScheduler();
      engine = MockRoutingEngine();
      cache = MockAudioCache();
      queue = createTestQueue(10);
    });
    
    tearDown(() {
      scheduler.dispose();
    });
    
    group('_prefetchedThroughIndex thread safety', () {
      test('concurrent prefetch operations update index atomically', () async {
        // Setup context
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        // Run multiple prefetch operations concurrently
        final futures = <Future<void>>[];
        
        // Start regular prefetch
        futures.add(scheduler.runPrefetch(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 3,
          shouldContinue: () => true,
        ));
        
        // Immediately start another prefetch with different target
        // This simulates the race condition
        futures.add(scheduler.runPrefetch(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 5,
          shouldContinue: () => true,
        ));
        
        await Future.wait(futures);
        
        // Index should be at least 3 (the minimum completed prefetch)
        expect(scheduler.prefetchedThroughIndex, greaterThanOrEqualTo(3));
      });
      
      test('immediate prefetch and regular prefetch dont conflict', () async {
        // Setup context
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        // Run immediate and regular prefetch concurrently
        final futures = <Future<void>>[];
        
        // Start immediate prefetch for segment 1
        futures.add(scheduler.prefetchNextSegmentImmediately(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
          shouldContinue: () => true,
        ));
        
        // Start regular prefetch
        futures.add(scheduler.runPrefetch(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 5,
          shouldContinue: () => true,
        ));
        
        await Future.wait(futures);
        
        // Index should be monotonically increasing (never decreases)
        expect(scheduler.prefetchedThroughIndex, greaterThanOrEqualTo(1));
      });
      
      test('index never decreases during concurrent updates', () async {
        // Setup context
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        // Track all index values seen
        final indexHistory = <int>[];
        int lastSeen = -1;
        
        // Monitor index changes
        final timer = Timer.periodic(Duration(milliseconds: 1), (_) {
          final current = scheduler.prefetchedThroughIndex;
          if (current != lastSeen) {
            indexHistory.add(current);
            lastSeen = current;
          }
        });
        
        // Run many concurrent operations
        final futures = <Future<void>>[];
        for (var i = 0; i < 5; i++) {
          futures.add(scheduler.prefetchNextSegmentImmediately(
            engine: engine,
            cache: cache,
            queue: queue,
            voiceId: 'voice1',
            playbackRate: 1.0,
            currentIndex: i,
            shouldContinue: () => true,
          ));
        }
        
        await Future.wait(futures);
        timer.cancel();
        
        // Verify index only increases (monotonic)
        for (var i = 1; i < indexHistory.length; i++) {
          expect(indexHistory[i], greaterThanOrEqualTo(indexHistory[i - 1]),
            reason: 'Index should never decrease: history = $indexHistory');
        }
      });
      
      test('bufferUntilReady and prefetch dont conflict', () async {
        // Use slower synthesis to increase chance of overlap
        final slowEngine = MockRoutingEngine(
          synthesisDelay: Duration(milliseconds: 20),
        );
        
        // Setup context
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        // Run buffer and prefetch concurrently
        final futures = <Future<void>>[];
        
        futures.add(scheduler.bufferUntilReady(
          engine: slowEngine,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
          shouldContinue: () => true,
        ));
        
        futures.add(scheduler.runPrefetch(
          engine: slowEngine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 5,
          shouldContinue: () => true,
        ));
        
        await Future.wait(futures);
        
        // Should complete without errors and index should be valid
        expect(scheduler.prefetchedThroughIndex, greaterThanOrEqualTo(0));
        expect(scheduler.prefetchedThroughIndex, lessThan(queue.length));
      });
    });
    
    group('context invalidation', () {
      test('prefetch aborts when context changes', () async {
        // Setup initial context
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        // Use slow engine
        final slowEngine = MockRoutingEngine(
          synthesisDelay: Duration(milliseconds: 50),
        );
        
        // Start prefetch
        final prefetchFuture = scheduler.runPrefetch(
          engine: slowEngine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 5,
          shouldContinue: () => true,
        );
        
        // Wait a bit then change context
        await Future.delayed(Duration(milliseconds: 30));
        scheduler.updateContext(
          bookId: 'book2', // Different book
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        await prefetchFuture;
        
        // Prefetch should have aborted early
        expect(slowEngine.synthesizeCalls, lessThan(5));
      });
    });
    
    group('reset behavior', () {
      test('reset clears prefetched index', () async {
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        await scheduler.runPrefetch(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 3,
          shouldContinue: () => true,
        );
        
        expect(scheduler.prefetchedThroughIndex, greaterThan(0));
        
        scheduler.reset();
        
        expect(scheduler.prefetchedThroughIndex, equals(-1));
        expect(scheduler.isRunning, isFalse);
      });
    });
    
    group('cached segments', () {
      test('skips synthesis for cached segments', () async {
        // Pre-cache segment 1
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: 'voice1',
          text: queue[1].text,
          playbackRate: 1.0,
        );
        cache.setReady(cacheKey);
        
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        await scheduler.runPrefetch(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 2,
          shouldContinue: () => true,
        );
        
        // Prefetch starts from currentIndex+1=1, goes to targetIndex=2
        // Segment 1 is cached, segment 2 needs synthesis = 1 call
        expect(engine.synthesizeCalls, equals(1));
      });
      
      test('immediate prefetch skips cached segment', () async {
        // Pre-cache segment 1
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: 'voice1',
          text: queue[1].text,
          playbackRate: 1.0,
        );
        cache.setReady(cacheKey);
        
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        await scheduler.prefetchNextSegmentImmediately(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
          shouldContinue: () => true,
        );
        
        // Should not have synthesized (segment was cached)
        expect(engine.synthesizeCalls, equals(0));
        // But index should still be updated
        expect(scheduler.prefetchedThroughIndex, equals(1));
      });
    });
    
    group('callbacks', () {
      test('calls onSynthesisStarted and onSynthesisComplete', () async {
        final started = <int>[];
        final completed = <int>[];
        
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        await scheduler.runPrefetch(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          targetIndex: 2,
          shouldContinue: () => true,
          onSynthesisStarted: started.add,
          onSynthesisComplete: completed.add,
        );
        
        expect(started, containsAll([1, 2]));
        expect(completed, containsAll([1, 2]));
      });
      
      test('immediate prefetch triggers callbacks', () async {
        final started = <int>[];
        final completed = <int>[];
        
        scheduler.updateContext(
          bookId: 'book1',
          chapterIndex: 0,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
        );
        
        await scheduler.prefetchNextSegmentImmediately(
          engine: engine,
          cache: cache,
          queue: queue,
          voiceId: 'voice1',
          playbackRate: 1.0,
          currentIndex: 0,
          shouldContinue: () => true,
          onSynthesisStarted: started.add,
          onSynthesisComplete: completed.add,
        );
        
        expect(started, contains(1));
        expect(completed, contains(1));
      });
    });
  });
}
