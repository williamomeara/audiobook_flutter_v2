/// Analyzes document structure for advanced boilerplate detection.
///
/// Complements BoilerplateRemover by detecting structural patterns:
/// - Preliminary sections (transcriber notes, editor notes)
/// - List-like boilerplate (glossaries, credits)
/// - Chapter-spanning patterns (repeated headers/footers)
class StructureAnalyzer {
  // Patterns that indicate start of preliminary sections
  static final _prelimininarySectionMarkers = [
    RegExp(r"transcriber'?s\s+notes?", caseSensitive: false),
    RegExp(r'explanatory\s+notes?', caseSensitive: false),
    RegExp(r'preliminary\s+matter', caseSensitive: false),
    RegExp(r"editor'?s?\s+notes?", caseSensitive: false),
    RegExp(r'foreword', caseSensitive: false),
    RegExp(r'introduction\s+by', caseSensitive: false),
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
  static String? extractPreliminarySection(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty) return null;

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
      if (line.length > 100 && !line.contains('note') && !line.contains('[')) {
        endIdx = i;
        return lines.sublist(startIdx, endIdx).join('\n');
      }
    }

    // If no natural end found, take up to first empty line
    for (int i = startIdx + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) {
        endIdx = i;
        break;
      }
    }

    return lines.sublist(startIdx, endIdx).join('\n');
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
