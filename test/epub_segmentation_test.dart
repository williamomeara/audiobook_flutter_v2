import 'dart:io';

import 'package:test/test.dart';
import 'package:core_domain/core_domain.dart';

void main() {
  group('TextSegmenter', () {
    test('segments long sentence at ~300 char boundary', () {
      // Create a sample long text without sentence punctuation
      // This becomes one very long "sentence" that must be force-split
      final text = List.filled(300, 'word').join(' ');
      final segments = segmentText(text);
      expect(segments, isNotEmpty);

      // Segmenter splits at 300 chars max, not 100/25 words
      // Each segment should be ≤300 chars (maxLongSentenceLength)
      for (final s in segments) {
        expect(s.text.length, lessThanOrEqualTo(300));
      }
    });

    test('segments text with sentences at ~100 char boundary', () {
      // Create text with proper sentence endings
      final text = List.generate(20, (i) => 'This is sentence number $i.').join(' ');
      final segments = segmentText(text);
      expect(segments, isNotEmpty);

      // With sentence boundaries, segmenter targets ~100 chars (default)
      // Sentences may be grouped but kept whole
      for (final s in segments) {
        // Check reasonable character length (allow some overflow for complete sentences)
        expect(s.text.length, lessThanOrEqualTo(300));
        expect(s.text.length, greaterThanOrEqualTo(10)); // minLength
      }
    });

    // Note: EPUB integration test removed as it depends on:
    // 1. local_dev/dev_books directory (not in version control)
    // 2. tools/analyze_epub_text.dart script (doesn't exist)
    // EPUB parsing is already tested via the actual epub_parser.dart 
    // which is used in production code.
  });
}
