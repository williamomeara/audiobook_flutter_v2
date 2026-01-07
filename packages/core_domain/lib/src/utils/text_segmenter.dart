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
  // Default set to 20 words ≈ 100 characters (avg 5 chars/word)
  // Only breaks on sentence endings (. ! ?)
  static const int defaultMaxLength = 100;

  /// Maximum length before forced split (for very long sentences).
  // Much larger than default to avoid breaking sentences unnecessarily
  static const int maxLongSentenceLength = 300;

  /// Minimum characters for a valid segment.
  static const int minLength = 10;

  /// Segment text into a list of segments.
  ///
  /// [text] - The input text to segment.
  /// [maxLength] - Target maximum characters per segment (default ~100, ~20 words).
  ///               Sentences are kept whole unless they exceed maxLongSentenceLength.
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
      // If adding this sentence would exceed max length AND current chunk is not empty
      // Keep sentences whole by starting a new segment
      if (currentChunk.isNotEmpty && 
          currentChunk.length + sentence.length + 1 > maxLength) {
        // Save current chunk
        final text = currentChunk.toString().trim();
        if (text.length >= minLength) {
          segments.add(Segment(text: text, index: segmentIndex++));
        }
        currentChunk.clear();
      }

      // If sentence itself is extremely long (> maxLongSentenceLength), split it
      // This is the only case where we break mid-sentence
      if (sentence.length > maxLongSentenceLength) {
        if (currentChunk.isNotEmpty) {
          final text = currentChunk.toString().trim();
          if (text.length >= minLength) {
            segments.add(Segment(text: text, index: segmentIndex++));
          }
          currentChunk.clear();
        }
        
        final subSegments = _splitLongSentence(sentence, maxLongSentenceLength);
        for (final sub in subSegments) {
          if (sub.length >= minLength) {
            segments.add(Segment(text: sub, index: segmentIndex++));
          }
        }
      } else {
        // Add sentence to current chunk
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

  /// Find a good break point within maxLength for very long sentences.
  /// Only used when sentence exceeds maxLongSentenceLength (~300 chars).
  static int _findBreakPoint(String text, int maxLength) {
    final searchText = text.substring(0, maxLength);

    // For very long sentences, try to break at clause boundaries
    // Priority: semicolon > comma > colon > dash > space
    for (final delimiter in ['; ', ', ', ': ', ' - ']) {
      final lastIndex = searchText.lastIndexOf(delimiter);
      if (lastIndex > maxLength ~/ 2) {  // Must be past halfway point
        return lastIndex + delimiter.length;
      }
    }

    // Fall back to last space if no punctuation found
    final lastSpace = searchText.lastIndexOf(' ');
    if (lastSpace > maxLength ~/ 2) {
      return lastSpace + 1;
    }

    return -1;
  }
}

/// Convenience function for segmenting text.
/// Segments at sentence boundaries (. ! ?) targeting ~20 words per segment.
List<Segment> segmentText(String text, {int maxLength = 100}) {
  return TextSegmenter.segment(text, maxLength: maxLength);
}
