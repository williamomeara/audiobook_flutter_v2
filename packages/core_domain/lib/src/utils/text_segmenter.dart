import '../models/segment.dart';
import 'text_normalizer.dart';

/// Segments text into synthesis-friendly chunks.
///
/// Segments are designed to:
/// - Be short enough for efficient synthesis
/// - Break at natural pause points (sentences)
/// - Avoid cutting words or awkward breaks
class TextSegmenter {
  TextSegmenter._();

  /// Default maximum characters per segment.
  static const int defaultMaxLength = 500;

  /// Minimum characters for a valid segment.
  static const int minLength = 10;

  /// Segment text into a list of segments.
  ///
  /// [text] - The input text to segment.
  /// [maxLength] - Maximum characters per segment (default 500).
  ///
  /// Returns a list of [Segment] objects.
  static List<Segment> segment(
    String text, {
    int maxLength = defaultMaxLength,
  }) {
    final normalized = TextNormalizer.normalize(text);
    if (normalized.isEmpty) return const [];

    final segments = <Segment>[];
    final sentences = _splitIntoSentences(normalized);

    var currentChunk = StringBuffer();
    var segmentIndex = 0;

    for (final sentence in sentences) {
      // If adding this sentence would exceed max length
      if (currentChunk.length + sentence.length + 1 > maxLength) {
        // Save current chunk if it has content
        if (currentChunk.isNotEmpty) {
          final text = currentChunk.toString().trim();
          if (text.length >= minLength) {
            segments.add(Segment(text: text, index: segmentIndex++));
          }
          currentChunk.clear();
        }

        // If the sentence itself is too long, split it
        if (sentence.length > maxLength) {
          final subSegments = _splitLongSentence(sentence, maxLength);
          for (final sub in subSegments) {
            if (sub.length >= minLength) {
              segments.add(Segment(text: sub, index: segmentIndex++));
            }
          }
        } else {
          currentChunk.write(sentence);
        }
      } else {
        if (currentChunk.isNotEmpty) currentChunk.write(' ');
        currentChunk.write(sentence);
      }
    }

    // Add remaining content
    if (currentChunk.isNotEmpty) {
      final text = currentChunk.toString().trim();
      if (text.length >= minLength) {
        segments.add(Segment(text: text, index: segmentIndex));
      }
    }

    return segments;
  }

  /// Split text into sentences.
  static List<String> _splitIntoSentences(String text) {
    // Split on sentence-ending punctuation followed by space or end
    final sentencePattern = RegExp(
      r'(?<=[.!?])\s+(?=[A-Z])|(?<=[.!?])$',
    );

    final parts = text.split(sentencePattern);
    return parts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Split a long sentence at natural break points.
  static List<String> _splitLongSentence(String sentence, int maxLength) {
    final result = <String>[];
    var remaining = sentence;

    while (remaining.length > maxLength) {
      // Find the best break point
      var breakPoint = _findBreakPoint(remaining, maxLength);

      if (breakPoint <= 0) {
        // No good break point found, force break at maxLength
        breakPoint = maxLength;
      }

      result.add(remaining.substring(0, breakPoint).trim());
      remaining = remaining.substring(breakPoint).trim();
    }

    if (remaining.isNotEmpty) {
      result.add(remaining);
    }

    return result;
  }

  /// Find a good break point within maxLength.
  static int _findBreakPoint(String text, int maxLength) {
    final searchText = text.substring(0, maxLength);

    // Prefer breaking at clause boundaries (comma, semicolon, colon)
    for (final delimiter in ['; ', ', ', ': ', ' - ']) {
      final lastIndex = searchText.lastIndexOf(delimiter);
      if (lastIndex > maxLength ~/ 3) {
        return lastIndex + delimiter.length;
      }
    }

    // Fall back to last space
    final lastSpace = searchText.lastIndexOf(' ');
    if (lastSpace > maxLength ~/ 3) {
      return lastSpace + 1;
    }

    return -1;
  }
}

/// Convenience function for segmenting text.
List<Segment> segmentText(String text, {int maxLength = 500}) {
  return TextSegmenter.segment(text, maxLength: maxLength);
}
