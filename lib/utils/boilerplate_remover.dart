import 'dart:math';

/// Removes boilerplate text from ebook content.
///
/// Handles:
/// - Project Gutenberg headers and footers
/// - Scanner notes and OCR attribution
/// - Source attribution (Z-Library, LibGen)
/// - Repeated text patterns across chapters
class BoilerplateRemover {
  // Project Gutenberg start markers
  static final _pgStartMarkers = [
    RegExp(
      r'\*{3}\s*START OF (THIS|THE) PROJECT GUTENBERG EBOOK.*?\*{3}',
      caseSensitive: false,
      dotAll: true,
    ),
    RegExp(
      r'The Project Gutenberg E-?[Bb]ook of[^\n]+',
      caseSensitive: false,
    ),
    RegExp(
      r'This eBook is for the use of anyone anywhere[^\n]*',
      caseSensitive: false,
    ),
  ];

  // Project Gutenberg end markers
  static final _pgEndMarkers = [
    RegExp(
      r'\*{3}\s*END OF (THIS|THE) PROJECT GUTENBERG EBOOK.*?\*{3}',
      caseSensitive: false,
    ),
    RegExp(
      r'End of (the )?Project Gutenberg',
      caseSensitive: false,
    ),
  ];

  // Content patterns that indicate boilerplate paragraphs
  static final _boilerplateIndicators = [
    // Project Gutenberg specific
    RegExp(r'produced by', caseSensitive: false),
    RegExp(r'this file should be named', caseSensitive: false),
    RegExp(r'www\.gutenberg\.org', caseSensitive: false),
    RegExp(r'gutenberg\.org', caseSensitive: false),
    RegExp(r'public domain', caseSensitive: false),
    RegExp(r'project gutenberg', caseSensitive: false),

    // General scanner/OCR attribution
    RegExp(r'scanned by', caseSensitive: false),
    RegExp(r'proofread by', caseSensitive: false),
    RegExp(r'digitized by', caseSensitive: false),
    RegExp(r'ocr\s*(errors|quality)', caseSensitive: false),
    RegExp(r'internet archive', caseSensitive: false),
    RegExp(r'archive\.org', caseSensitive: false),

    // Z-Library / Library Genesis
    RegExp(r'z-library', caseSensitive: false),
    RegExp(r'libgen', caseSensitive: false),
    RegExp(r'b-ok\.cc', caseSensitive: false),
    RegExp(r'library genesis', caseSensitive: false),

    // Page numbers alone
    RegExp(r'^\s*\d+\s*$'),
    RegExp(r'^\s*-\s*\d+\s*-\s*$'),
    RegExp(r'^\s*\[\s*\d+\s*\]\s*$'),
  ];

  /// Removes Project Gutenberg (and similar) boilerplate from full book text.
  ///
  /// This method:
  /// 1. Finds START marker and removes everything before it (including the marker)
  /// 2. Finds END marker and removes everything after it (including the marker)
  ///
  /// Returns the cleaned content.
  static String removeFromBook(String content) {
    var result = content;

    // Find and remove PG header (everything up to and including START marker)
    for (final pattern in _pgStartMarkers) {
      final match = pattern.firstMatch(result);
      if (match != null) {
        result = result.substring(match.end).trimLeft();
        break;
      }
    }

    // Find and remove PG footer (everything from END marker onwards)
    for (final pattern in _pgEndMarkers) {
      final match = pattern.firstMatch(result);
      if (match != null) {
        result = result.substring(0, match.start).trimRight();
        break;
      }
    }

    return result;
  }

  /// Removes boilerplate paragraphs from chapter content.
  ///
  /// Checks the first and last few paragraphs of each chapter
  /// for boilerplate indicators like scanner notes, page numbers, etc.
  ///
  /// Returns the cleaned chapter content.
  static String cleanChapter(String content) {
    final paragraphs = content.split(RegExp(r'\n\s*\n'));

    if (paragraphs.isEmpty) return content;

    // Filter leading boilerplate (check first 3 paragraphs)
    int startIdx = 0;
    final maxLeading = min(3, paragraphs.length);
    for (int i = 0; i < maxLeading; i++) {
      if (_isBoilerplate(paragraphs[i])) {
        startIdx = i + 1;
      } else {
        break;
      }
    }

    // Filter trailing boilerplate (check last 3 paragraphs)
    int endIdx = paragraphs.length;
    final minTrailing = max(startIdx, paragraphs.length - 3);
    for (int i = paragraphs.length - 1; i >= minTrailing; i--) {
      if (_isBoilerplate(paragraphs[i])) {
        endIdx = i;
      } else {
        break;
      }
    }

    // Safety: don't remove everything
    if (startIdx >= endIdx) return content.trim();

    return paragraphs.sublist(startIdx, endIdx).join('\n\n').trim();
  }

  /// Checks if a paragraph is likely boilerplate.
  ///
  /// A paragraph is considered boilerplate if:
  /// - It's empty or whitespace only
  /// - It matches any boilerplate indicator pattern
  static bool _isBoilerplate(String paragraph) {
    final trimmed = paragraph.trim();

    // Empty paragraphs are boilerplate
    if (trimmed.isEmpty) return true;

    // Check against indicator patterns first (regardless of length)
    for (final pattern in _boilerplateIndicators) {
      if (pattern.hasMatch(trimmed)) return true;
    }

    return false;
  }

  /// Detects repeated text appearing at the start of multiple chapters.
  ///
  /// If the same text appears in >50% of chapters, it's likely boilerplate
  /// that was inserted programmatically (e.g., scanner headers).
  ///
  /// Returns the repeated prefix if found, null otherwise.
  static String? detectRepeatedPrefix(List<String> chapterContents) {
    if (chapterContents.length < 3) return null;

    final prefixes = <String, int>{};
    for (final content in chapterContents) {
      final lines = content.split('\n');
      if (lines.isEmpty) continue;

      final firstLine = lines.first.trim();
      if (firstLine.length > 10 && firstLine.length < 200) {
        prefixes[firstLine] = (prefixes[firstLine] ?? 0) + 1;
      }
    }

    // Return prefix if it appears in >50% of chapters
    for (final entry in prefixes.entries) {
      if (entry.value > chapterContents.length * 0.5) {
        return entry.key;
      }
    }
    return null;
  }

  /// Detects repeated text appearing at the end of multiple chapters.
  ///
  /// Similar to detectRepeatedPrefix but for chapter endings.
  ///
  /// Returns the repeated suffix if found, null otherwise.
  static String? detectRepeatedSuffix(List<String> chapterContents) {
    if (chapterContents.length < 3) return null;

    final suffixes = <String, int>{};
    for (final content in chapterContents) {
      final lines = content.split('\n');
      if (lines.isEmpty) continue;

      final lastLine = lines.last.trim();
      if (lastLine.length > 10 && lastLine.length < 200) {
        suffixes[lastLine] = (suffixes[lastLine] ?? 0) + 1;
      }
    }

    // Return suffix if it appears in >50% of chapters
    for (final entry in suffixes.entries) {
      if (entry.value > chapterContents.length * 0.5) {
        return entry.key;
      }
    }
    return null;
  }

  /// Removes a known repeated prefix from chapter content.
  static String removePrefix(String content, String prefix) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith(prefix)) {
      return trimmed.substring(prefix.length).trimLeft();
    }
    return content;
  }

  /// Removes a known repeated suffix from chapter content.
  static String removeSuffix(String content, String suffix) {
    final trimmed = content.trimRight();
    if (trimmed.endsWith(suffix)) {
      return trimmed.substring(0, trimmed.length - suffix.length).trimRight();
    }
    return content;
  }

  /// Checks if text contains Project Gutenberg boilerplate.
  ///
  /// Useful for quick detection before processing.
  static bool hasProjectGutenbergBoilerplate(String content) {
    for (final pattern in _pgStartMarkers) {
      if (pattern.hasMatch(content)) return true;
    }
    for (final pattern in _pgEndMarkers) {
      if (pattern.hasMatch(content)) return true;
    }
    return false;
  }
}
