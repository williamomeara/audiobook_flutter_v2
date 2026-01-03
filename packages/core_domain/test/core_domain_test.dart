import 'package:test/test.dart';
import 'package:core_domain/core_domain.dart';

void main() {
  group('TextSegmenter', () {
    test('segments empty text returns empty list', () {
      expect(segmentText(''), isEmpty);
      expect(segmentText('   '), isEmpty);
    });

    test('segments short text into single segment', () {
      const text = 'This is a short sentence.';
      final segments = segmentText(text);
      expect(segments.length, 1);
      expect(segments[0].text, text);
      expect(segments[0].index, 0);
    });

    test('segments multiple sentences', () {
      const text =
          'First sentence here. Second sentence here. Third sentence here.';
      final segments = segmentText(text, maxLength: 100);
      expect(segments.isNotEmpty, true);
      // All segments should have content
      for (final s in segments) {
        expect(s.text.isNotEmpty, true);
      }
    });

    test('respects max length', () {
      const text =
          'This is a long paragraph with many words that should be split into multiple segments based on the maximum length parameter we provide to the segmenter function.';
      final segments = segmentText(text, maxLength: 50);
      for (final s in segments) {
        // Some variance allowed for word boundaries
        expect(s.text.length <= 60, true);
      }
    });

    test('segment indices are sequential', () {
      const text =
          'First sentence. Second sentence. Third sentence. Fourth sentence.';
      final segments = segmentText(text, maxLength: 50);
      for (var i = 0; i < segments.length; i++) {
        expect(segments[i].index, i);
      }
    });
  });

  group('TextNormalizer', () {
    test('normalizes whitespace', () {
      expect(TextNormalizer.normalize('hello   world'), 'hello world');
      expect(TextNormalizer.normalize('  hello  '), 'hello');
      expect(TextNormalizer.normalize('line\none'), 'line one');
    });

    test('normalizes quotes', () {
      expect(TextNormalizer.normalize('"hello"'), '"hello"');
      expect(TextNormalizer.normalize("'world'"), "'world'");
    });

    test('normalizes dashes', () {
      expect(TextNormalizer.normalize('word–word'), 'word-word');
      expect(TextNormalizer.normalize('word—word'), 'word-word');
    });

    test('normalizes ellipsis', () {
      expect(TextNormalizer.normalize('wait…'), 'wait...');
    });
  });

  group('CacheKeyGenerator', () {
    test('generates deterministic keys', () {
      final key1 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Hello world',
        playbackRate: 1.0,
      );
      final key2 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Hello world',
        playbackRate: 1.0,
      );
      expect(key1.textHash, key2.textHash);
      expect(key1.voiceId, key2.voiceId);
    });

    test('different text produces different hashes', () {
      final key1 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Hello world',
        playbackRate: 1.0,
      );
      final key2 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Goodbye world',
        playbackRate: 1.0,
      );
      expect(key1.textHash, isNot(key2.textHash));
    });

    test('generates valid filename', () {
      final key = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Test text',
        playbackRate: 1.0,
      );
      final filename = key.toFilename();
      expect(filename.endsWith('.wav'), true);
      expect(filename.contains('kokoro_af'), true);
    });

    test('rate-independent synthesis uses 1.0 rate', () {
      final key1 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Test',
        playbackRate: 1.5,
      );
      final key2 = CacheKeyGenerator.generate(
        voiceId: 'kokoro_af',
        text: 'Test',
        playbackRate: 2.0,
      );
      // With rate-independent synthesis, same text should produce same key
      expect(key1.synthesisRate, key2.synthesisRate);
      expect(key1.textHash, key2.textHash);
    });
  });

  group('TimeEstimator', () {
    test('estimates duration for text', () {
      const text = 'This is a test sentence with some words in it.';
      final duration = estimateDurationMs(text);
      expect(duration > 0, true);
    });

    test('faster rate produces shorter duration', () {
      const text = 'Test sentence';
      final normal = estimateDurationMs(text, playbackRate: 1.0);
      final fast = estimateDurationMs(text, playbackRate: 2.0);
      expect(fast < normal, true);
    });

    test('empty text produces zero duration', () {
      expect(estimateDurationMs(''), 0);
    });

    test('formats duration correctly', () {
      expect(TimeEstimator.formatDuration(90000), '1:30');
      expect(TimeEstimator.formatDuration(3661000), '1:01:01');
      expect(TimeEstimator.formatDuration(5000), '0:05');
    });
  });

  group('VoiceIds', () {
    test('identifies engine types correctly', () {
      expect(VoiceIds.isSupertonic('supertonic_m1'), true);
      expect(VoiceIds.isSupertonic('kokoro_af'), false);

      expect(VoiceIds.isKokoro('kokoro_af'), true);
      expect(VoiceIds.isKokoro('supertonic_m1'), false);

      expect(VoiceIds.isPiper('piper:en_US-lessac-medium'), true);
      expect(VoiceIds.isPiper('kokoro_af'), false);
    });

    test('gets correct engine for voice', () {
      expect(VoiceIds.engineFor('device'), EngineType.device);
      expect(VoiceIds.engineFor('supertonic_m1'), EngineType.supertonic);
      expect(VoiceIds.engineFor('kokoro_af'), EngineType.kokoro);
      expect(VoiceIds.engineFor('piper:en_US-lessac-medium'), EngineType.piper);
    });

    test('gets Kokoro speaker IDs', () {
      expect(VoiceIds.kokoroSpeakerId('kokoro_af'), 0);
      expect(VoiceIds.kokoroSpeakerId('kokoro_am_adam'), 5);
      expect(VoiceIds.kokoroSpeakerId('unknown'), 0);
    });

    test('extracts Piper model keys', () {
      expect(
        VoiceIds.piperModelKey('piper:en_US-lessac-medium'),
        'en_US-lessac-medium',
      );
      expect(VoiceIds.piperModelKey('kokoro_af'), null);
    });
  });

  group('IdGenerator', () {
    test('generates unique IDs', () {
      final ids = List.generate(100, (_) => generateId());
      final unique = ids.toSet();
      expect(unique.length, ids.length);
    });

    test('generates IDs of correct length', () {
      expect(generateId(length: 8).length, 8);
      expect(generateId(length: 16).length, 16);
    });

    test('generates prefixed IDs', () {
      final id = IdGenerator.generatePrefixed('test');
      expect(id.startsWith('test_'), true);
    });
  });

  group('Book model', () {
    test('serializes and deserializes correctly', () {
      final book = Book(
        id: 'test_book',
        title: 'Test Title',
        author: 'Test Author',
        filePath: '/path/to/book.epub',
        addedAt: 1234567890,
        chapters: [
          Chapter(id: 'ch1', number: 1, title: 'Chapter 1', content: 'Content'),
        ],
        progress: BookProgress(chapterIndex: 0, segmentIndex: 5),
      );

      final json = book.toJson();
      final restored = Book.fromJson(json);

      expect(restored.id, book.id);
      expect(restored.title, book.title);
      expect(restored.author, book.author);
      expect(restored.chapters.length, 1);
      expect(restored.progress.segmentIndex, 5);
    });
  });
}
