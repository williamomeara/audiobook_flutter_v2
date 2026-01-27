import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart' show SegmentReadiness, SegmentState;
import 'package:audiobook_flutter_v2/app/playback_providers.dart' show SegmentReadinessTracker;

void main() {
  late SegmentReadinessTracker tracker;

  setUp(() {
    tracker = SegmentReadinessTracker.instance;
    // Reset tracker state between tests
    tracker.reset('test-key');
  });

  group('SegmentReadinessTracker', () {
    test('getReadiness returns empty map for unknown key', () {
      final readiness = tracker.getReadiness('unknown-key');
      expect(readiness, isEmpty);
    });

    test('getForSegment returns null for unknown segment', () {
      final result = tracker.getForSegment('test-key', 0);
      expect(result, isNull);
    });

    test('opacityForSegment returns default for unknown segment', () {
      final opacity = tracker.opacityForSegment('test-key', 0);
      expect(opacity, 0.4);
    });

    test('onSynthesisStarted marks segment as synthesizing', () {
      tracker.onSynthesisStarted('test-key', 0);
      
      final readiness = tracker.getForSegment('test-key', 0);
      expect(readiness, isNotNull);
      expect(readiness!.state, SegmentState.synthesizing);
    });

    test('onSynthesisComplete marks segment as ready', () {
      tracker.onSynthesisStarted('test-key', 0);
      tracker.onSynthesisComplete('test-key', 0);
      
      final readiness = tracker.getForSegment('test-key', 0);
      expect(readiness, isNotNull);
      expect(readiness!.state, SegmentState.ready);
    });

    test('onSegmentQueued marks segment as queued', () {
      tracker.onSegmentQueued('test-key', 0);
      
      final readiness = tracker.getForSegment('test-key', 0);
      expect(readiness, isNotNull);
      expect(readiness!.state, SegmentState.queued);
    });

    test('onSegmentQueued does not downgrade ready segment', () {
      tracker.onSynthesisComplete('test-key', 0);
      tracker.onSegmentQueued('test-key', 0);
      
      final readiness = tracker.getForSegment('test-key', 0);
      expect(readiness!.state, SegmentState.ready);
    });

    test('onSegmentQueued does not downgrade synthesizing segment', () {
      tracker.onSynthesisStarted('test-key', 0);
      tracker.onSegmentQueued('test-key', 0);
      
      final readiness = tracker.getForSegment('test-key', 0);
      expect(readiness!.state, SegmentState.synthesizing);
    });

    test('initializeFromCache sets multiple segments as ready', () {
      tracker.initializeFromCache('test-key', [0, 2, 5, 10]);
      
      final readiness = tracker.getReadiness('test-key');
      expect(readiness.length, 4);
      expect(readiness[0]!.state, SegmentState.ready);
      expect(readiness[2]!.state, SegmentState.ready);
      expect(readiness[5]!.state, SegmentState.ready);
      expect(readiness[10]!.state, SegmentState.ready);
      expect(readiness[1], isNull); // Not in cache
    });

    test('reset clears all readiness for a key', () {
      tracker.onSynthesisComplete('test-key', 0);
      tracker.onSynthesisComplete('test-key', 1);
      tracker.onSynthesisComplete('test-key', 2);
      
      expect(tracker.getReadiness('test-key').length, 3);
      
      tracker.reset('test-key');
      
      expect(tracker.getReadiness('test-key'), isEmpty);
    });

    test('onSegmentEvicted downgrades ready segment', () {
      tracker.onSynthesisComplete('test-key', 0);
      expect(tracker.getForSegment('test-key', 0)!.state, SegmentState.ready);
      
      tracker.onSegmentEvicted('test-key', 0);
      
      expect(tracker.getForSegment('test-key', 0)!.state, SegmentState.notQueued);
    });

    test('onSegmentEvicted does not affect non-ready segments', () {
      tracker.onSynthesisStarted('test-key', 0);
      tracker.onSegmentEvicted('test-key', 0);
      
      // Still synthesizing, not downgraded
      expect(tracker.getForSegment('test-key', 0)!.state, SegmentState.synthesizing);
    });

    test('stream emits updates', () async {
      final updates = <Map<int, SegmentReadiness>>[];
      final subscription = tracker.stream('stream-test').listen(updates.add);
      
      // Allow stream to initialize
      await Future.delayed(Duration.zero);
      
      tracker.onSynthesisStarted('stream-test', 0);
      await Future.delayed(Duration.zero);
      
      tracker.onSynthesisComplete('stream-test', 0);
      await Future.delayed(Duration.zero);
      
      await subscription.cancel();
      
      expect(updates.length, greaterThanOrEqualTo(2));
    });

    test('different keys are independent', () {
      tracker.onSynthesisComplete('key-a', 0);
      tracker.onSynthesisComplete('key-b', 0);
      tracker.onSynthesisComplete('key-b', 1);
      
      expect(tracker.getReadiness('key-a').length, 1);
      expect(tracker.getReadiness('key-b').length, 2);
    });

    test('verifyAgainstCache detects evicted segments', () async {
      // Set up segments as ready
      tracker.onSynthesisComplete('verify-key', 0);
      tracker.onSynthesisComplete('verify-key', 1);
      tracker.onSynthesisComplete('verify-key', 2);
      
      // Mock cache that says segment 1 is no longer cached
      Future<bool> mockCacheCheck(int index) async {
        return index != 1; // 0 and 2 are cached, 1 is not
      }
      
      final evicted = await tracker.verifyAgainstCache(
        key: 'verify-key',
        isSegmentCached: mockCacheCheck,
        startIndex: 0,
        windowSize: 3,
      );
      
      expect(evicted, [1]);
      expect(tracker.getForSegment('verify-key', 1)!.state, SegmentState.notQueued);
    });
  });

  group('SegmentReadiness opacity', () {
    test('ready segment has full opacity', () {
      tracker.onSynthesisComplete('opacity-test', 0);
      expect(tracker.opacityForSegment('opacity-test', 0), 1.0);
    });

    test('synthesizing segment has partial opacity', () {
      tracker.onSynthesisStarted('opacity-test', 0);
      final opacity = tracker.opacityForSegment('opacity-test', 0);
      expect(opacity, greaterThan(0.4));
      expect(opacity, lessThan(1.0));
    });

    test('queued segment has lower opacity', () {
      tracker.onSegmentQueued('opacity-test', 0);
      final opacity = tracker.opacityForSegment('opacity-test', 0);
      expect(opacity, greaterThanOrEqualTo(0.4));
      expect(opacity, lessThan(1.0));
    });
  });
}
