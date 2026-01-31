import '../models/segment.dart';
import 'text_normalizer.dart';

/// Internal helper class for splitting text around figures.
class _TextChunk {
  const _TextChunk({
    required this.text,
    this.isFigure = false,
    this.imagePath,
    this.altText,
    this.width,
    this.height,
  });
  
  final String text;
  final bool isFigure;
  final String? imagePath;
  final String? altText;
  final int? width;
  final int? height;
}

/// Segments text into synthesis-friendly chunks.
///
/// Segments are designed to:
/// - Be short enough for efficient synthesis
/// - Break at natural pause points (sentences)
/// - Avoid cutting words or awkward breaks
/// - Recognize and preserve figure placeholders as separate segments
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
  
  /// Pattern to match figure placeholders: [FIGURE:{path}:{alt}:{width}:{height}]
  /// Width and height are optional for backwards compatibility.
  static final RegExp _figurePattern = RegExp(
    r'\[FIGURE:([^:]+):([^:\]]*?)(?::(\d+):(\d+))?\]',
  );

  /// Segment text into a list of segments.
  ///
  /// [text] - The input text to segment.
  /// [maxLength] - Target maximum characters per segment (default ~100, ~20 words).
  ///               Sentences are kept whole unless they exceed maxLongSentenceLength.
  ///
  /// Returns a list of [Segment] objects, including figure segments with proper type.
  static List<Segment> segment(
    String text, {
    int maxLength = defaultMaxLength,
  }) {
    // First, split text into chunks around figure placeholders
    final chunks = _splitAroundFigures(text);
    
    final segments = <Segment>[];
    var segmentIndex = 0;
    
    for (final chunk in chunks) {
      if (chunk.isFigure) {
        // Create a figure segment with metadata including dimensions
        final metadata = <String, dynamic>{
          'imagePath': chunk.imagePath,
          'altText': chunk.altText ?? 'Image',
        };
        // Add dimensions if available
        if (chunk.width != null) metadata['width'] = chunk.width;
        if (chunk.height != null) metadata['height'] = chunk.height;
        
        segments.add(Segment(
          text: chunk.altText ?? 'Image',
          index: segmentIndex++,
          type: SegmentType.figure,
          metadata: metadata,
        ));
      } else {
        // Segment normal text
        final textSegments = _segmentText(chunk.text, maxLength, segmentIndex);
        for (final seg in textSegments) {
          segments.add(seg);
          segmentIndex++;
        }
      }
    }
    
    // Re-index all segments to ensure continuous indices
    return segments.asMap().entries.map((e) => 
      e.value.copyWith(index: e.key)
    ).toList();
  }
  
  /// Split text into chunks, separating figure placeholders from regular text.
  static List<_TextChunk> _splitAroundFigures(String text) {
    final chunks = <_TextChunk>[];
    var lastEnd = 0;
    
    for (final match in _figurePattern.allMatches(text)) {
      // Add text before this figure (if any)
      if (match.start > lastEnd) {
        final beforeText = text.substring(lastEnd, match.start).trim();
        if (beforeText.isNotEmpty) {
          chunks.add(_TextChunk(text: beforeText));
        }
      }
      
      // Add the figure with dimensions if available
      final widthStr = match.group(3);
      final heightStr = match.group(4);
      chunks.add(_TextChunk(
        text: match.group(0) ?? '',
        isFigure: true,
        imagePath: match.group(1),
        altText: match.group(2),
        width: widthStr != null ? int.tryParse(widthStr) : null,
        height: heightStr != null ? int.tryParse(heightStr) : null,
      ));
      
      lastEnd = match.end;
    }
    
    // Add remaining text after last figure (if any)
    if (lastEnd < text.length) {
      final afterText = text.substring(lastEnd).trim();
      if (afterText.isNotEmpty) {
        chunks.add(_TextChunk(text: afterText));
      }
    }
    
    // If no figures found, return the whole text as a single chunk
    if (chunks.isEmpty && text.trim().isNotEmpty) {
      chunks.add(_TextChunk(text: text));
    }
    
    return chunks;
  }
  
  /// Segment a chunk of regular text (no figures).
  static List<Segment> _segmentText(String text, int maxLength, int startIndex) {
    final normalized = TextNormalizer.normalize(text);
    if (normalized.isEmpty) return const [];

    final segments = <Segment>[];
    final sentences = _splitIntoSentences(normalized);

    var currentChunk = StringBuffer();
    var segmentIndex = startIndex;

    for (final sentence in sentences) {
      // If adding this sentence would exceed max length AND current chunk is not empty
      // Keep sentences whole by starting a new segment
      if (currentChunk.isNotEmpty && 
          currentChunk.length + sentence.length + 1 > maxLength) {
        // Save current chunk
        final chunkText = currentChunk.toString().trim();
        if (chunkText.length >= minLength) {
          segments.add(Segment(text: chunkText, index: segmentIndex++));
        }
        currentChunk.clear();
      }

      // If sentence itself is extremely long (> maxLongSentenceLength), split it
      // This is the only case where we break mid-sentence
      if (sentence.length > maxLongSentenceLength) {
        if (currentChunk.isNotEmpty) {
          final chunkText = currentChunk.toString().trim();
          if (chunkText.length >= minLength) {
            segments.add(Segment(text: chunkText, index: segmentIndex++));
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
      final chunkText = currentChunk.toString().trim();
      if (chunkText.length >= minLength) {
        segments.add(Segment(text: chunkText, index: segmentIndex));
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
