import 'package:core_domain/core_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/synthesis/synthesis_request.dart';

void main() {
  group('SynthesisRequest', () {
    test('compareTo prioritizes higher priority first', () {
      final immediateReq = SynthesisRequest(
        track: _createTrack(0),
        voiceId: 'voice1',
        playbackRate: 1.0,
        segmentIndex: 0,
        priority: SynthesisPriority.immediate,
        cacheKey: _createCacheKey('text0'),
        bookId: 'book1',
        chapterIndex: 0,
      );

      final prefetchReq = SynthesisRequest(
        track: _createTrack(1),
        voiceId: 'voice1',
        playbackRate: 1.0,
        segmentIndex: 1,
        priority: SynthesisPriority.prefetch,
        cacheKey: _createCacheKey('text1'),
        bookId: 'book1',
        chapterIndex: 0,
      );

      final backgroundReq = SynthesisRequest(
        track: _createTrack(2),
        voiceId: 'voice1',
        playbackRate: 1.0,
        segmentIndex: 2,
        priority: SynthesisPriority.background,
        cacheKey: _createCacheKey('text2'),
        bookId: 'book1',
        chapterIndex: 0,
      );

      // Immediate should come before prefetch
      expect(immediateReq.compareTo(prefetchReq), lessThan(0));
      // Prefetch should come before background
      expect(prefetchReq.compareTo(backgroundReq), lessThan(0));
      // Immediate should come before background
      expect(immediateReq.compareTo(backgroundReq), lessThan(0));
    });

    test('compareTo uses FIFO for same priority', () {
      final earlierReq = SynthesisRequest(
        track: _createTrack(0),
        voiceId: 'voice1',
        playbackRate: 1.0,
        segmentIndex: 0,
        priority: SynthesisPriority.prefetch,
        cacheKey: _createCacheKey('text0'),
        createdAt: DateTime(2024, 1, 1, 12, 0, 0),
        bookId: 'book1',
        chapterIndex: 0,
      );

      final laterReq = SynthesisRequest(
        track: _createTrack(1),
        voiceId: 'voice1',
        playbackRate: 1.0,
        segmentIndex: 1,
        priority: SynthesisPriority.prefetch,
        cacheKey: _createCacheKey('text1'),
        createdAt: DateTime(2024, 1, 1, 12, 0, 1),
        bookId: 'book1',
        chapterIndex: 0,
      );

      // Earlier request should come first (negative comparison)
      expect(earlierReq.compareTo(laterReq), lessThan(0));
    });

    test('upgradePriority only upgrades, never downgrades', () {
      final req = SynthesisRequest(
        track: _createTrack(0),
        voiceId: 'voice1',
        playbackRate: 1.0,
        segmentIndex: 0,
        priority: SynthesisPriority.prefetch,
        cacheKey: _createCacheKey('text0'),
        bookId: 'book1',
        chapterIndex: 0,
      );

      // Should upgrade
      req.upgradePriority(SynthesisPriority.immediate);
      expect(req.priority, SynthesisPriority.immediate);

      // Should not downgrade
      req.upgradePriority(SynthesisPriority.background);
      expect(req.priority, SynthesisPriority.immediate);
    });
  });

  group('SynthesisPriority', () {
    test('values are ordered correctly', () {
      expect(SynthesisPriority.immediate.value, greaterThan(SynthesisPriority.prefetch.value));
      expect(SynthesisPriority.prefetch.value, greaterThan(SynthesisPriority.background.value));
    });
  });
}

AudioTrack _createTrack(int index) {
  return AudioTrack(
    id: 'track_$index',
    bookId: 'book1',
    chapterIndex: 0,
    segmentIndex: index,
    text: 'This is segment $index text',
  );
}

CacheKey _createCacheKey(String text) {
  return CacheKeyGenerator.generate(
    voiceId: 'test_voice',
    text: text,
    playbackRate: 1.0,
  );
}
