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

    // NEW: Production credits variations
    RegExp(r'e-?text\s+(prepared|produced)\s+by', caseSensitive: false),
    RegExp(r'html\s+version', caseSensitive: false),
    RegExp(r'transcribed?\s+by', caseSensitive: false),

    // NEW: Project Gutenberg running headers
    // Catches patterns like "Book Title | Project Gutenberg CHAPTER X..."
    RegExp(r'\|\s*project\s+gutenberg.*?chapter\s+\d+', caseSensitive: false),

    // NEW: License/copyright markers
    RegExp(r'distributed\s+under', caseSensitive: false),
    RegExp(r'creative\s+commons', caseSensitive: false),
    RegExp(r'this work is in the public domain', caseSensitive: false),

    // NEW: Formatting/encoding notices
    RegExp(r'utf-?8.*encoded', caseSensitive: false),
    RegExp(r'chapter\s+divisions?.*?added', caseSensitive: false),
    RegExp(r'the\s+following.*?was\s+(added|removed)', caseSensitive: false),

    // NEW: Special character/editor notes
    RegExp(r'(unknown|illegible|indecipherable).*?character', caseSensitive: false),
    RegExp(r'character.*?represented\s+as', caseSensitive: false),
    RegExp(r'\[note.*?editor\]', caseSensitive: false),
    RegExp(r'\[footnote', caseSensitive: false),
    RegExp(r'\[illustration', caseSensitive: false),

    // NEW: Conversion artifacts
    RegExp(r'paragraph\s+(break|marker)', caseSensitive: false),
    RegExp(r'original\s+(pagination|formatting)', caseSensitive: false),
    RegExp(r'line\s+breaks?.*?(preserved|added)', caseSensitive: false),
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
  /// or a repeated header (like book title) that was inserted.
  ///
  /// Returns the repeated prefix if found, null otherwise.
  static String? detectRepeatedPrefix(List<String> chapterContents, {String? bookTitle}) {
    if (chapterContents.length < 3) return null;

    final prefixes = <String, int>{};
    for (final content in chapterContents) {
      final lines = content.split('\n');
      if (lines.isEmpty) continue;

      final firstLine = lines.first.trim();
      if (firstLine.length > 5 && firstLine.length < 300) {
        prefixes[firstLine] = (prefixes[firstLine] ?? 0) + 1;
      }
    }

    // Return prefix if it appears in >50% of chapters
    for (final entry in prefixes.entries) {
      if (entry.value > chapterContents.length * 0.5) {
        return entry.key;
      }
    }
    
    // If no repeated first lines, check for common string prefixes
    // This catches cases like PG headers embedded without newlines
    final nonEmptyContents = chapterContents.where((c) => c.length > 20).toList();
    if (nonEmptyContents.length < 3) return null;
    
    // Find longest common prefix among >50% of chapters
    final firstContent = nonEmptyContents.first;
    for (int prefixLen = 80; prefixLen >= 10; prefixLen -= 5) {
      if (prefixLen > firstContent.length) continue;
      final candidate = firstContent.substring(0, prefixLen);
      
      final matchCount = nonEmptyContents.where((c) => c.startsWith(candidate)).length;
      if (matchCount > nonEmptyContents.length * 0.5) {
        // Return if it looks like boilerplate OR matches the book title
        if (_looksLikeBoilerplatePrefix(candidate)) {
          return candidate;
        }
        // NEW: Also remove repeated book title prefix
        if (bookTitle != null && _isTitlePrefix(candidate, bookTitle)) {
          return candidate;
        }
        // NEW: Check if it's a repeated exact line (even without boilerplate patterns)
        // If >70% of chapters have the exact same prefix, it's likely redundant
        if (matchCount > nonEmptyContents.length * 0.7) {
          return candidate;
        }
      }
    }
    
    return null;
  }
  
  /// Check if a prefix is essentially the book title (possibly with chapter marker).
  static bool _isTitlePrefix(String prefix, String bookTitle) {
    final lowerPrefix = prefix.toLowerCase().trim();
    final lowerTitle = bookTitle.toLowerCase().trim();
    
    // Direct match
    if (lowerPrefix == lowerTitle) return true;
    
    // Prefix starts with book title
    if (lowerPrefix.startsWith(lowerTitle)) return true;
    
    // Book title starts with prefix
    if (lowerTitle.startsWith(lowerPrefix)) return true;
    
    // Handle partial matches (e.g., "A Conjuring" matches "A Conjuring of Light")
    final prefixWords = lowerPrefix.split(RegExp(r'\\s+'));
    final titleWords = lowerTitle.split(RegExp(r'\\s+'));
    if (prefixWords.length >= 2 && titleWords.length >= 2) {
      // If the first 2+ words match, it's likely the title
      final matchingWords = prefixWords.take(titleWords.length).toList();
      final titlePart = titleWords.take(matchingWords.length).toList();
      if (matchingWords.length >= 2 && matchingWords.join(' ') == titlePart.join(' ')) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Detect and remove repeated chapter titles from segment content.
  /// 
  /// This handles patterns like:
  /// - "Book Title Chapter 1 Actual content..."
  /// - "Book Title: A Subtitle Prologue The story begins..."
  /// 
  /// Called after initial chapter segmentation to clean up first segments.
  static String removeRepeatedTitleFromContent(String content, String bookTitle, String chapterTitle) {
    if (content.isEmpty || bookTitle.isEmpty) return content;
    
    var result = content.trim();
    final lowerContent = result.toLowerCase();
    final lowerBookTitle = bookTitle.toLowerCase().trim();
    final lowerChapterTitle = chapterTitle.toLowerCase().trim();
    
    // Check if content starts with book title (exact or close match)
    if (lowerContent.startsWith(lowerBookTitle)) {
      // Remove the book title
      result = result.substring(bookTitle.length).trimLeft();
      
      // Also remove any separator characters after the title
      result = result.replaceFirst(RegExp(r'^[:\|,\-–—]\s*'), '');
    }
    
    // Check for "Book Title Chapter X" pattern
    final titleChapterPattern = RegExp(
      '^${RegExp.escape(lowerBookTitle)}\\s*(?:chapter|prologue|epilogue|part|section)?\\s*\\d*\\s*',
      caseSensitive: false,
    );
    if (titleChapterPattern.hasMatch(result)) {
      result = result.replaceFirst(titleChapterPattern, '').trimLeft();
    }
    
    // Check for just the chapter title at the start (if different from content)
    if (lowerChapterTitle.isNotEmpty && !lowerChapterTitle.startsWith('chapter')) {
      if (lowerContent.startsWith(lowerChapterTitle) && 
          lowerContent.length > lowerChapterTitle.length) {
        // Don't remove if it's meaningful content, only if it looks like a header
        final afterTitle = content.substring(chapterTitle.length).trimLeft();
        // Only remove if followed by content (not just more title)
        if (afterTitle.isNotEmpty && afterTitle[0].toUpperCase() == afterTitle[0]) {
          result = afterTitle;
        }
      }
    }
    
    return result;
  }
  
  /// Check if a prefix looks like boilerplate rather than legitimate content.
  static bool _looksLikeBoilerplatePrefix(String prefix) {
    final lower = prefix.toLowerCase();
    
    // Project Gutenberg and similar
    if (lower.contains('project gutenberg')) return true;
    if (lower.contains('gutenberg.org')) return true;
    
    // Converter/scanner attribution
    if (lower.contains('converter')) return true;
    if (lower.contains('generated by')) return true;
    if (lower.contains('scanned')) return true;
    if (lower.contains('digitized')) return true;
    
    // Library attributions
    if (lower.contains('z-library')) return true;
    if (lower.contains('libgen')) return true;
    if (lower.contains('archive.org')) return true;
    
    // Copyright notices repeated in every chapter
    if (lower.contains('copyright')) return true;
    if (lower.contains('all rights reserved')) return true;
    
    return false;
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
