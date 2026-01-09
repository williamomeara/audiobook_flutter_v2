/// Segments text into sentences for TTS processing.
///
/// Handles common edge cases:
/// - Abbreviations (Dr., Mr., etc.)
/// - Decimals (3.14)
/// - Initials (J.K. Rowling)
/// - Multiple punctuation (Wait...)
/// - Quotation boundaries
class SentenceSegmenter {
  // Common abbreviations that don't end sentences
  static const _abbreviations = {
    // Titles
    'dr', 'mr', 'mrs', 'ms', 'prof', 'sr', 'jr', 'rev', 'hon', 'gov', 'gen',
    'col', 'lt', 'sgt', 'capt', 'cmdr', 'adm',
    // Common abbreviations
    'vs', 'etc', 'inc', 'ltd', 'co', 'corp', 'bros',
    // Months
    'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct',
    'nov', 'dec',
    // Locations
    'st', 'ave', 'blvd', 'rd', 'mt', 'ft',
    // Latin abbreviations - stored as full form with periods stripped
    'ie', 'eg', 'cf', 'viz', 'al', 'et',
    // Misc
    'no', 'vol', 'pg', 'pp', 'ch', 'pt', 'fig', 'approx',
  };

  // Pattern for potential sentence break
  // Matches: sentence-ending punctuation (optionally followed by quote) + whitespace + uppercase letter or quote
  // Uses Unicode ranges for uppercase letters to handle É, Ü, etc.
  // Note: Using non-raw string to allow Unicode escapes for curly quotes
  static final _breakCandidate = RegExp(
    r'([.!?]+["\x27\u201C\u201D\u2018\u2019]?)(\s+)([A-Z\u00C0-\u00D6\u00D8-\u00DE"\x27\u201C\u201D\u2018\u2019])',
    multiLine: true,
  );

  // Pattern to extract the last word before punctuation
  static final _lastWordPattern = RegExp(r'(\S+)\s*$');

  /// Segment text into sentences
  static List<String> segment(String text) {
    if (text.trim().isEmpty) return [];

    final sentences = <String>[];
    var remaining = text;
    var searchStart = 0;

    while (searchStart < remaining.length) {
      final match =
          _breakCandidate.firstMatch(remaining.substring(searchStart));
      if (match == null) {
        // No more breaks found
        final lastPart = remaining.trim();
        if (lastPart.isNotEmpty) {
          sentences.add(lastPart);
        }
        break;
      }

      final absoluteMatchStart = searchStart + match.start;
      final textBeforePunc = remaining.substring(0, absoluteMatchStart);
      final punctuation = match.group(1)!;
      final afterPunc = match.group(3)!;

      // Check if this is a real sentence break
      if (_shouldSkipBreak(textBeforePunc, punctuation, afterPunc)) {
        // Not a real break - continue searching after the punctuation
        searchStart = absoluteMatchStart + punctuation.length;
        continue;
      }

      // Real sentence break found
      final sentenceEnd = absoluteMatchStart + punctuation.length;
      final sentence = remaining.substring(0, sentenceEnd).trim();
      if (sentence.isNotEmpty) {
        sentences.add(sentence);
      }

      // Continue from after the whitespace
      final nextStart = sentenceEnd + match.group(2)!.length;
      remaining = remaining.substring(nextStart);
      searchStart = 0;
    }

    return sentences.where((s) => s.isNotEmpty).toList();
  }

  /// Determine if we should skip this potential break
  static bool _shouldSkipBreak(
      String textBefore, String punctuation, String afterPunc) {
    // Only apply decimal/abbreviation rules for single periods
    if (punctuation == '.') {
      // Check for decimal: digit followed by period followed by digit
      if (_isDecimalContext(textBefore, afterPunc)) {
        return true;
      }

      // Check for abbreviation
      if (_isAbbreviation(textBefore)) {
        return true;
      }
    }

    return false;
  }

  /// Check if the text ends with an abbreviation
  static bool _isAbbreviation(String textBefore) {
    final match = _lastWordPattern.firstMatch(textBefore);
    if (match == null) return false;

    final lastWord = match.group(1)!.toLowerCase();
    // Remove all periods and check
    final cleaned = lastWord.replaceAll('.', '');

    // Single letter is likely an initial (A. B. Smith)
    if (cleaned.length == 1 && RegExp(r'[a-z]').hasMatch(cleaned)) {
      return true;
    }

    // Two-letter abbreviations that commonly have periods (i.e., e.g.)
    if (cleaned.length == 2 && _abbreviations.contains(cleaned)) {
      return true;
    }

    return _abbreviations.contains(cleaned);
  }

  /// Check if this looks like a decimal number context
  /// "3.14" followed by period is a sentence end
  /// "3." followed by digit would be mid-decimal (but we're looking at . followed by capital)
  static bool _isDecimalContext(String textBefore, String afterPunc) {
    // If the character after the period is not a letter, might be decimal
    // But our regex already ensures afterPunc is uppercase, so this is a sentence end
    // The only case to skip is if we have "X.Y" pattern where Y is a letter
    // Since afterPunc is uppercase, this IS a sentence boundary for "3.14. It"

    // Actually, we want to detect "10.30. Do" where 10.30 is a time
    // But "Pi is 3.14. It" should split. The difference is context.
    // For simplicity: if textBefore ends with \d\.\d+ pattern, it's likely a number
    // and the next period IS a sentence end.

    // Check for cases like "section 3.a" where we shouldn't split
    // This is: ends with digit, has period somewhere before
    // Actually let's be more careful: only skip if textBefore ends with just a digit
    // and we're in a clear mid-word context

    // For TTS purposes, let's be conservative and split on "number. Capital"
    // since "3.14. It" should split but "10.30. D" for time might not
    // We'll keep it simple: don't skip for decimal-like patterns when followed by capital
    return false;
  }

  /// Convenience method: segment and return count
  static int countSentences(String text) {
    return segment(text).length;
  }

  /// Segment text into sentences with position info
  /// Returns list of (startIndex, endIndex, sentence) tuples
  static List<SentenceSpan> segmentWithSpans(String text) {
    if (text.trim().isEmpty) return [];

    final spans = <SentenceSpan>[];
    final sentences = segment(text);

    var searchStart = 0;
    for (final sentence in sentences) {
      // Find where this sentence starts in the original text
      // Skip leading whitespace
      while (searchStart < text.length &&
          RegExp(r'\s').hasMatch(text[searchStart])) {
        searchStart++;
      }

      final startIndex = searchStart;
      final endIndex = startIndex + sentence.length;
      spans.add(SentenceSpan(
        start: startIndex,
        end: endIndex,
        text: sentence,
      ));

      searchStart = endIndex;
    }

    return spans;
  }
}

/// Represents a sentence with its position in the original text
class SentenceSpan {
  final int start;
  final int end;
  final String text;

  const SentenceSpan({
    required this.start,
    required this.end,
    required this.text,
  });

  int get length => end - start;

  @override
  String toString() => 'SentenceSpan($start-$end: "$text")';

  @override
  bool operator ==(Object other) =>
      other is SentenceSpan &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}
