/// Analyzes document structure for advanced boilerplate detection.
///
/// Complements BoilerplateRemover by detecting structural patterns:
/// - Preliminary sections (transcriber notes, editor notes)
/// - List-like boilerplate (glossaries, credits)
/// - Chapter-spanning patterns (repeated headers/footers)
class StructureAnalyzer {
  // Patterns that indicate start of preliminary sections
  // IMPORTANT: Only match sections explicitly marked as notes/preliminary matter
  // Do NOT match book titles, table of contents, or introductions that are part of the book
  static final _prelimininarySectionMarkers = [
    RegExp(r"transcriber'?s\s+notes?", caseSensitive: false),
    RegExp(r"original\s+transcriber'?s\s+notes?", caseSensitive: false),
    RegExp(r'explanatory\s+notes?', caseSensitive: false),
    RegExp(r'preliminary\s+matter', caseSensitive: false),
    RegExp(r"editor'?s?\s+notes?(?:\s+on\s+the\s+text)?", caseSensitive: false),
    RegExp(r'production\s+notes?', caseSensitive: false),
  ];

  // Patterns that mark end of sections
  static final _sectionEndMarkers = [
    RegExp(r'^(?:book|chapter|part|section|volume)\s+\d+', caseSensitive: false),
    RegExp(r'^(?:book|chapter|part|section|volume)\s+[a-z]+', caseSensitive: false),
    RegExp(r'^---+$'),
    RegExp(r'^\*{3,}$'),
  ];

  /// Extracts preliminary section boilerplate from chapter content.
  ///
  /// Looks for sections like "TRANSCRIBER'S NOTES" that come at the start
  /// of a chapter and are followed by actual content.
  ///
  /// Returns the preliminary section text if found, null otherwise.
  ///
  /// IMPORTANT: Only removes sections that are explicitly preliminary notes,
  /// not table of contents, introductions, or other book matter.
  static String? extractPreliminarySection(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty) return null;

    // Safety check: Don't process if content looks like it has book metadata/TOC
    // (table of contents indicators suggest this is structural metadata, not a real preliminary section)
    if (content.contains('CONTENTS') &&
        content.contains('CHAPTER') &&
        content.contains('| Project Gutenberg')) {
      return null;
    }

    // Find first line that matches preliminary markers
    int startIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      for (final pattern in _prelimininarySectionMarkers) {
        if (pattern.hasMatch(line)) {
          startIdx = i;
          break;
        }
      }
      if (startIdx != -1) break;
    }

    if (startIdx == -1) return null;

    // Find where the section ends (next major heading or content)
    int endIdx = startIdx + 1;
    for (int i = startIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();

      // Stop at major section markers
      for (final pattern in _sectionEndMarkers) {
        if (pattern.hasMatch(line)) {
          endIdx = i;
          // Don't include this line in the preliminary section
          return lines.sublist(startIdx, endIdx).join('\n');
        }
      }

      // Stop at substantial content (multi-paragraph real text)
      // If we've moved past a few lines of notes and hit real content, stop
      if (i > startIdx + 10 && line.length > 150) {
        endIdx = i;
        return lines.sublist(startIdx, endIdx).join('\n');
      }
    }

    // If no natural end found, take only up to first significant empty line
    // (preliminary sections should be brief, not consume the whole chapter)
    var emptyLineCount = 0;
    for (int i = startIdx + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) {
        emptyLineCount++;
        if (emptyLineCount >= 2) {
          endIdx = i;
          break;
        }
      } else {
        emptyLineCount = 0;
      }
    }

    final result = lines.sublist(startIdx, endIdx).join('\n');

    // Safety: don't return sections that are suspiciously large
    // Real preliminary sections should be <5000 words
    if (result.split(RegExp(r'\s+')).length > 5000) {
      return null;
    }

    return result;
  }

  /// Checks if a paragraph looks like a list (glossary, credits, etc).
  ///
  /// A paragraph is considered list-like if:
  /// - It has >5 lines
  /// - 70%+ of lines are short (<80 characters)
  /// - Lines follow similar patterns (bullet points, dashes, etc)
  static bool isListBoilerplate(String paragraph) {
    final lines = paragraph.split('\n').where((l) => l.trim().isNotEmpty).toList();

    // Need at least 5 lines to be a list
    if (lines.length < 5) return false;

    // Count short lines
    final shortLines = lines.where((line) => line.trim().length < 80).length;
    final shortPercentage = shortLines / lines.length;

    // 70%+ of lines should be short
    if (shortPercentage < 0.7) return false;

    // Check for list-like patterns (bullets, dashes, etc)
    final hasListPattern = lines.any((line) {
      final trimmed = line.trim();
      return trimmed.startsWith('•') ||
          trimmed.startsWith('-') ||
          trimmed.startsWith('*') ||
          trimmed.startsWith(RegExp(r'^\d+\.')) ||
          trimmed.startsWith('[');
    });

    // If it has list patterns, it's likely a list
    if (hasListPattern) return true;

    // Otherwise, check if lines are consistently short (could be credits)
    return shortPercentage > 0.85;
  }

  /// Detects boilerplate lines that appear at the same position in multiple chapters.
  ///
  /// Analyzes the first 5 lines of each chapter and finds patterns that appear
  /// in 80%+ of chapters at the same line position. These are likely repeated
  /// boilerplate inserted by the converter.
  ///
  /// Returns a set of lines to filter out.
  static Set<String> detectChapterSpanningBoilerplate(List<String> chapters) {
    if (chapters.length < 3) return {};

    final boilerplateLines = <String>{};

    // Analyze first 5 lines of each chapter
    for (int lineIdx = 0; lineIdx < 5; lineIdx++) {
      final lineOccurrences = <String, int>{};

      for (final chapter in chapters) {
        final lines = chapter.split('\n');
        if (lineIdx < lines.length) {
          final line = lines[lineIdx].trim();
          // Include all non-empty lines (even very short ones)
          if (line.isNotEmpty) {
            lineOccurrences[line] = (lineOccurrences[line] ?? 0) + 1;
          }
        }
      }

      // If a line appears in 80%+ of chapters at this position, it's boilerplate
      for (final entry in lineOccurrences.entries) {
        if (entry.value >= chapters.length * 0.8) {
          boilerplateLines.add(entry.key);
        }
      }
    }

    // Filter out very common words that might appear naturally
    final commonWords = <String>{
      'chapter',
      'part',
      'book',
      'section',
      'volume',
    };

    return boilerplateLines
        .where((line) => !commonWords.any((word) => line.toLowerCase().startsWith(word)))
        .toSet();
  }
}
