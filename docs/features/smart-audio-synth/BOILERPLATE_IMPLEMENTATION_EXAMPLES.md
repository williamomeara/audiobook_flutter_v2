# Boilerplate Optimization - Complete Code Examples

## 1. StructureAnalyzer Class

```dart
/// Detects and removes structured boilerplate patterns from EPUB content
class StructureAnalyzer {
  /// Extracts known preliminary sections (TRANSCRIBER'S NOTES, etc)
  static String? extractPreliminarySection(String content) {
    final preliminaryPattern = RegExp(
      r'(?:PRELIMINARY|TRANSCRIBER|EXPLANATORY|EDITOR)[\'S]*\s*(?:NOTES|MATTER)',
      caseSensitive: false,
    );

    final match = preliminaryPattern.firstMatch(content);
    if (match == null) return null;

    // Find next major section
    final nextSectionPattern = RegExp(r'\n\n\w+\s*\n', multiline: true);
    final nextMatch = nextSectionPattern.firstMatch(content.substring(match.end));

    if (nextMatch != null) {
      return content.substring(match.start, match.end + nextMatch.start);
    }
    return null;
  }

  /// Detects list-like structures (glossaries, credits) that are likely boilerplate
  static bool isListBoilerplate(String para) {
    final lines = para.split('\n');
    if (lines.length < 5) return false;

    // If 70%+ of lines are short (< 80 chars), likely a list
    final shortLines = lines.where((l) => l.length < 80).length;
    return shortLines > lines.length * 0.7;
  }

  /// Removes patterns that appear at same position in 80%+ of chapters
  static void removeChapterSpanningBoilerplate(List<String> chapters) {
    if (chapters.length < 3) return;

    final patterns = <int, Map<String, int>>{}; // position -> pattern -> count

    // Analyze first 5 lines of each chapter
    for (final chapter in chapters) {
      final lines = chapter.split('\n').take(5).toList();
      for (int i = 0; i < lines.length; i++) {
        final pattern = lines[i].trim();
        if (pattern.length > 3 && pattern.length < 200) {
          patterns.putIfAbsent(i, () => {});
          patterns[i]![pattern] = (patterns[i]![pattern] ?? 0) + 1;
        }
      }
    }

    // Find repeating patterns at >80% threshold
    final threshold = (chapters.length * 0.8).ceil();
    final boilerplateLines = <String>{};

    for (final posPatterns in patterns.values) {
      for (final entry in posPatterns.entries) {
        if (entry.value >= threshold && !_looksLikeRealContent(entry.key)) {
          boilerplateLines.add(entry.key);
        }
      }
    }

    // Remove from each chapter
    for (int i = 0; i < chapters.length; i++) {
      chapters[i] = chapters[i]
          .split('\n')
          .where((line) => !boilerplateLines.contains(line.trim()))
          .join('\n');
    }
  }

  static bool _looksLikeRealContent(String line) {
    // Check if this looks like actual story content, not boilerplate
    if (line.isEmpty) return false;

    // Short lines that look like boilerplate
    if (line.length < 10) return false;

    // Common boilerplate patterns
    final boilerplateKeywords = [
      'chapter',
      'page',
      '***',
      '---',
      'book',
      'part',
      'volume',
    ];

    final lowerLine = line.toLowerCase();
    if (boilerplateKeywords.any((kw) => lowerLine.contains(kw))) {
      return true; // These are chapter markers, not boilerplate
    }

    return true; // Looks like content
  }
}
```

## 2. SegmentConfidenceScorer Class

```dart
/// Scores segment confidence (likelihood of being actual content vs boilerplate)
class SegmentConfidenceScorer {
  static const _boilerplateIndicators = [
    'produced by',
    'scanned by',
    'ocr errors',
    'transcribed by',
    'project gutenberg',
    'www.gutenberg.org',
    'public domain',
    'distributed under',
    'creative commons',
    '[footnote',
    '[illustration',
    '[note',
    '[unnumbered',
  ];

  /// Main scoring function
  static SegmentScore scoreSegment(
    String text,
    int position, // position in chapter (0 = first)
    int totalSegments,
    List<String>? chapterFrontMatter,
  ) {
    double confidence = 1.0;
    final reasons = <String>[];

    // Factor 1: Boilerplate indicators
    final boilerplateScore = _checkBoilerplateIndicators(text);
    if (boilerplateScore < 1.0) {
      confidence *= boilerplateScore;
      if (boilerplateScore == 0.0) {
        reasons.add('Definite boilerplate detected');
      }
    }

    // Factor 2: Content length
    final lengthScore = _getLengthScore(text);
    confidence *= lengthScore;
    if (lengthScore < 0.9) {
      reasons.add('Short segment: ${text.length} chars');
    }

    // Factor 3: Position in chapter
    final positionScore = _getPositionScore(position, totalSegments);
    confidence *= positionScore;
    if (positionScore < 1.0) {
      final percent = (position / totalSegments * 100).round();
      reasons.add('Position: $percent% through chapter');
    }

    // Factor 4: Grammar quality
    final grammarScore = _checkGrammarQuality(text);
    confidence *= grammarScore;
    if (grammarScore < 0.95) {
      reasons.add('Grammar issues detected');
    }

    // Factor 5: Front matter likelihood
    if (chapterFrontMatter != null && chapterFrontMatter.isNotEmpty) {
      final fmScore = _checkFrontMatterLikelihood(text, chapterFrontMatter);
      confidence *= fmScore;
      if (fmScore < 1.0) {
        reasons.add('May be preliminary matter');
      }
    }

    return SegmentScore(
      confidence: confidence.clamp(0.0, 1.0),
      reasons: reasons,
    );
  }

  static double _checkBoilerplateIndicators(String text) {
    int matches = 0;
    final lowerText = text.toLowerCase();

    for (final indicator in _boilerplateIndicators) {
      if (lowerText.contains(indicator)) {
        matches++;
      }
    }

    if (matches > 0) return 0.0; // Definite boilerplate
    return 1.0;
  }

  static double _getLengthScore(String text) {
    final length = text.length;
    if (length < 10) return 0.3; // Very short
    if (length < 30) return 0.5; // Short
    if (length < 100) return 0.8; // Medium
    return 1.0; // Full segment
  }

  static double _getPositionScore(int position, int total) {
    if (total < 5) return 1.0; // Skip check for short chapters

    final ratio = position / total;
    if (ratio < 0.1 || ratio > 0.9) {
      return 0.9; // First/last 10% less confident
    }
    return 1.0;
  }

  static double _checkGrammarQuality(String text) {
    var score = 1.0;

    // Check sentence structure
    final sentenceCount = text.split(RegExp(r'[.!?]')).length;
    final wordCount = text.split(' ').length;

    if (sentenceCount > 0) {
      final avgWords = wordCount / sentenceCount;
      // Expect 10-30 words per sentence
      if (avgWords < 3 || avgWords > 50) {
        score *= 0.8;
      }
    }

    // Check for balanced quotes
    if ((text.split('"').length - 1) % 2 != 0) {
      score *= 0.9; // Unbalanced quotes
    }

    return score;
  }

  static double _checkFrontMatterLikelihood(
    String text,
    List<String> frontMatter,
  ) {
    for (final fm in frontMatter) {
      if (text.contains(fm)) return 0.5;
    }
    return 1.0;
  }
}

class SegmentScore {
  final double confidence;
  final List<String> reasons;

  SegmentScore({
    required this.confidence,
    this.reasons = const [],
  });

  bool get isConfident => confidence >= 0.8;
  bool get isQuestionable => confidence >= 0.5 && confidence < 0.8;
  bool get isLikelyBoilerplate => confidence < 0.5;

  @override
  String toString() => 'SegmentScore($confidence, reasons=$reasons)';
}
```

## 3. OptimizedBookImporter Class

```dart
import 'dart:math';

/// Optimized book import with batch operations and confidence scoring
class OptimizedBookImporter {
  static Future<String> importBook(
    File file, {
    bool enableConfidenceScoring = true,
    bool batchInserts = true,
  }) async {
    // Phase 1: Parse
    final (book, chapters) = await parseEpub(file);

    // Phase 2: Process chapters with enhanced cleanup
    final processedChapters = await _processChaptersOptimized(
      chapters,
      enableConfidenceScoring: enableConfidenceScoring,
    );

    // Phase 3: Batch insert
    if (batchInserts) {
      return _batchInsertOptimized(book, processedChapters);
    } else {
      return _standardInsert(book, processedChapters);
    }
  }

  static Future<List<ProcessedChapter>> _processChaptersOptimized(
    List<Chapter> chapters, {
    required bool enableConfidenceScoring,
  }) async {
    final processed = <ProcessedChapter>[];
    final chapterTexts = chapters.map((c) => c.content).toList();

    // Detect repeated prefixes/suffixes
    final repeatedPrefix = BoilerplateRemover.detectRepeatedPrefix(chapterTexts);
    final repeatedSuffix = BoilerplateRemover.detectRepeatedSuffix(chapterTexts);

    for (final chapter in chapters) {
      var text = chapter.content;

      // Apply existing cleanup
      text = BoilerplateRemover.cleanChapter(text);

      // Remove repeated patterns
      if (repeatedPrefix != null) {
        text = BoilerplateRemover.removePrefix(text, repeatedPrefix);
      }
      if (repeatedSuffix != null) {
        text = BoilerplateRemover.removeSuffix(text, repeatedSuffix);
      }

      // NEW: Structure analysis
      final prelim = StructureAnalyzer.extractPreliminarySection(text);
      if (prelim != null) {
        text = text.replaceFirst(prelim, '');
      }

      // Segment with confidence scoring
      final segments = enableConfidenceScoring
          ? _segmentWithConfidence(text)
          : _segmentWithoutConfidence(text);

      processed.add(ProcessedChapter(
        chapter: chapter.copyWith(content: text),
        segments: segments,
      ));
    }

    return processed;
  }

  static List<ProcessedSegment> _segmentWithConfidence(String text) {
    final baseSegments = segmentText(text); // Your existing segmenter
    final processed = <ProcessedSegment>[];

    for (int i = 0; i < baseSegments.length; i++) {
      final score = SegmentConfidenceScorer.scoreSegment(
        baseSegments[i],
        i,
        baseSegments.length,
        null,
      );

      processed.add(ProcessedSegment(
        text: baseSegments[i],
        confidence: score.confidence,
        confidenceReason: score.reasons.join('; '),
      ));
    }

    return processed;
  }

  static List<ProcessedSegment> _segmentWithoutConfidence(String text) {
    final segments = segmentText(text);
    return segments
        .map((s) => ProcessedSegment(text: s, confidence: 1.0))
        .toList();
  }

  static Future<String> _batchInsertOptimized(
    Book book,
    List<ProcessedChapter> processedChapters,
  ) async {
    final db = await _getDatabase();

    return db.transaction((txn) async {
      // Insert book
      final bookMap = book.toMap();
      final bookId = await txn.insert('books', bookMap);

      // Prepare batch data
      final chapterMaps = <Map<String, dynamic>>[];
      final segmentMaps = <Map<String, dynamic>>[];

      for (int chIdx = 0; chIdx < processedChapters.length; chIdx++) {
        final proc = processedChapters[chIdx];

        // Chapter record
        final chapterMap = {
          'book_id': bookId,
          'chapter_index': chIdx,
          'title': proc.chapter.title,
          'segment_count': proc.segments.length,
          'word_count': proc.chapter.content.split(' ').length,
          'char_count': proc.chapter.content.length,
        };
        chapterMaps.add(chapterMap);

        // Segment records
        for (int segIdx = 0; segIdx < proc.segments.length; segIdx++) {
          final seg = proc.segments[segIdx];
          segmentMaps.add({
            'book_id': bookId,
            'chapter_index': chIdx,
            'segment_index': segIdx,
            'text': seg.text,
            'char_count': seg.text.length,
            'estimated_duration_ms': _estimateDuration(seg.text),
            'content_confidence': seg.confidence,
            'confidence_reason': seg.confidenceReason,
          });
        }
      }

      // Insert chapters
      for (final chapterMap in chapterMaps) {
        await txn.insert('chapters', chapterMap);
      }

      // Batch insert segments in chunks of 1000
      for (int i = 0; i < segmentMaps.length; i += 1000) {
        final chunk = segmentMaps.sublist(
          i,
          min(i + 1000, segmentMaps.length),
        );

        // Build multi-row INSERT
        final placeholders =
            chunk.map((_) => '(?, ?, ?, ?, ?, ?, ?, ?)').join(',');

        final values = chunk.expand((m) => [
          m['book_id'],
          m['chapter_index'],
          m['segment_index'],
          m['text'],
          m['char_count'],
          m['estimated_duration_ms'],
          m['content_confidence'],
          m['confidence_reason'] ?? '',
        ]).toList();

        await txn.rawInsert(
          'INSERT INTO segments '
          '(book_id, chapter_index, segment_index, text, char_count, '
          'estimated_duration_ms, content_confidence, confidence_reason) '
          'VALUES $placeholders',
          values,
        );
      }

      // Create indices after bulk insert
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_segments_book_chapter '
        'ON segments(book_id, chapter_index)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_segments_confidence '
        'ON segments(content_confidence)',
      );

      return bookId;
    });
  }

  static int _estimateDuration(String text) {
    // 150 WPM baseline, ~5 chars per word
    final ms = (text.length / 5 / 150 * 60 * 1000).round();
    return ms.clamp(500, 60000); // 0.5s to 60s
  }
}

class ProcessedChapter {
  final Chapter chapter;
  final List<ProcessedSegment> segments;

  ProcessedChapter({required this.chapter, required this.segments});
}

class ProcessedSegment {
  final String text;
  final double? confidence;
  final String? confidenceReason;

  ProcessedSegment({
    required this.text,
    this.confidence,
    this.confidenceReason,
  });
}
```

## 4. Integration: Updated EpubParser

```dart
// In infra/epub_parser.dart

Future<List<Chapter>> parseChaptersWithEnhancements(
  String content, {
  bool enableConfidenceScoring = true,
}) async {
  var chapters = await parseChapters(content);

  // NEW: Apply enhanced boilerplate removal
  chapters = chapters.map((ch) {
    var text = ch.content;

    // Existing cleanup
    text = BoilerplateRemover.cleanChapter(text);

    // NEW: Detect repeated patterns across all chapters
    final repeatedPrefix = BoilerplateRemover.detectRepeatedPrefix(
      chapters.map((c) => c.content).toList(),
    );
    if (repeatedPrefix != null) {
      text = BoilerplateRemover.removePrefix(text, repeatedPrefix);
    }

    // NEW: Remove structural boilerplate
    final prelim = StructureAnalyzer.extractPreliminarySection(text);
    if (prelim != null) {
      text = text.replaceFirst(prelim, '');
    }

    return ch.copyWith(content: text);
  }).toList();

  return chapters;
}
```

## 5. Integration: Updated TextSegmenter

```dart
// In packages/core_domain/lib/src/utils/text_segmenter.dart

List<Segment> segmentWithConfidence(
  String text,
  String bookId,
  int chapterIndex, {
  bool enableConfidence = true,
}) {
  final baseSegments = segmentText(text);

  if (!enableConfidence) {
    return baseSegments
        .asMap()
        .entries
        .map((e) => Segment(
              text: e.value,
              estimatedDurationMs: _estimateDuration(e.value),
            ))
        .toList();
  }

  // Score each segment
  return baseSegments.asMap().entries.map((entry) {
    final score = SegmentConfidenceScorer.scoreSegment(
      entry.value,
      entry.key,
      baseSegments.length,
      null,
    );

    return Segment(
      text: entry.value,
      estimatedDurationMs: _estimateDuration(entry.value),
      contentConfidence: score.confidence,
      confidenceReason: score.reasons.isEmpty ? null : score.reasons.join('; '),
    );
  }).toList();
}

int _estimateDuration(String text) {
  final ms = (text.length / 5 / 150 * 60 * 1000).round();
  return ms.clamp(500, 60000);
}
```

## Usage Example

```dart
// Simple usage:
final bookId = await OptimizedBookImporter.importBook(
  File('/path/to/book.epub'),
  enableConfidenceScoring: true,
  batchInserts: true,
);

// Check confidence levels in playback
final segments = await getSegmentsForChapter(bookId, 0);

for (final seg in segments) {
  if (seg.contentConfidence != null) {
    if (seg.contentConfidence! >= 0.8) {
      // High confidence - play normally
    } else if (seg.contentConfidence! >= 0.5) {
      // Medium confidence - show warning badge
      print('Questionable: ${seg.confidenceReason}');
    } else {
      // Low confidence - could skip based on user settings
      print('Likely boilerplate: ${seg.confidenceReason}');
    }
  }
}
```
