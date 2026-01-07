import 'dart:io';

import 'package:test/test.dart';
import 'package:core_domain/core_domain.dart';

void main() {
  group('TextSegmenter', () {
    test('segments sample text into ~20-word segments', () {
      // Create a sample long text
      final text = List.filled(300, 'word').join(' ');
      final segments = segmentText(text);
      expect(segments, isNotEmpty);

      for (final s in segments) {
        // Ensure segments are bounded in words and characters
        final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        expect(words, lessThanOrEqualTo(25));
        expect(s.text.length, lessThanOrEqualTo(120));
      }
    });

    // Note: EPUB integration test removed as it depends on:
    // 1. local_dev/dev_books directory (not in version control)
    // 2. tools/analyze_epub_text.dart script (doesn't exist)
    // EPUB parsing is already tested via the actual epub_parser.dart 
    // which is used in production code.
  });
}
