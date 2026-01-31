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

  /// Common abbreviations that should not be treated as sentence endings.
  /// These typically end with a period but are not sentence boundaries.
  static const _abbreviations = <String>[
    // Titles
    'Mr', 'Mrs', 'Ms', 'Miss', 'Dr', 'Prof', 'Rev', 'Sr', 'Jr', 'Esq',
    'Hon', 'Pres', 'Gov', 'Gen', 'Col', 'Lt', 'Cmdr', 'Sgt', 'Cpl',
    'Capt', 'Adm', 'Maj', 'Pvt',
    // Common abbreviations
    'St', 'Mt', 'Ft', 'Ave', 'Blvd', 'Rd', 'Ln', 'Ct', 'Sq', 'Pl',
    'Inc', 'Corp', 'Ltd', 'Co', 'LLC', 'Assn', 'Bros', 
    'vs', 'etc', 'e.g', 'i.e', 'viz', 'cf', 'al', 'et', 
    'approx', 'dept', 'est', 'govt', 'misc', 'no', 'nos',
    'vol', 'vols', 'pp', 'pg', 'ch', 'sec', 'para', 'fig', 'figs',
    'Jan', 'Feb', 'Mar', 'Apr', 'Jun', 'Jul', 'Aug', 'Sep', 'Sept', 
    'Oct', 'Nov', 'Dec', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  
  /// Pattern matching abbreviations (case insensitive)
  static final RegExp _abbreviationPattern = RegExp(
    r'\b(' + _abbreviations.join('|') + r')\.$',
    caseSensitive: false,
  );

  /// Split text into sentences.
  static List<String> _splitIntoSentences(String text) {
    // Split on sentence-ending punctuation followed by space or end
    // But NOT after common abbreviations
    final result = <String>[];
    var current = StringBuffer();
    final words = text.split(RegExp(r'(?<=\S)\s+'));
    
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      current.write(word);
      
      // Check if this word ends with sentence-ending punctuation
      if (RegExp(r'[.!?]$').hasMatch(word)) {
        // Check if it's an abbreviation
        final isAbbreviation = _abbreviationPattern.hasMatch(word);
        
        // Check if next word starts with capital letter (indicating new sentence)
        final nextWord = i + 1 < words.length ? words[i + 1] : null;
        final nextStartsWithCapital = nextWord != null && 
            RegExp(r'^[A-Z]').hasMatch(nextWord);
        
        // End sentence if:
        // 1. Not an abbreviation AND (next word is capitalized OR this is the last word)
        // 2. Exception: Always split on ! and ?
        if (word.endsWith('!') || word.endsWith('?') ||
            (!isAbbreviation && (nextStartsWithCapital || i == words.length - 1))) {
          result.add(current.toString().trim());
          current = StringBuffer();
          continue;
        }
      }
      
      // Add space before next word
      if (i < words.length - 1) {
        current.write(' ');
      }
    }
    
    // Add remaining text
    if (current.isNotEmpty) {
      result.add(current.toString().trim());
    }
    
    return result.where((s) => s.isNotEmpty).toList();
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
