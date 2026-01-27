import 'dart:math';

import 'package:core_domain/core_domain.dart';

/// Scores segment content confidence to identify front matter, boilerplate,
/// and actual story content.
/// 
/// Confidence ranges:
/// - 0.0-0.3: Likely front matter or boilerplate (TOC, copyright, scanner notes)
/// - 0.3-0.7: Uncertain (could be either)
/// - 0.7-1.0: Confident story content
class SegmentConfidenceScorer {
  SegmentConfidenceScorer._();

  // Patterns that strongly indicate front matter / boilerplate (low confidence)
  static final _boilerplatePatterns = [
    // Project Gutenberg patterns
    RegExp(r'Project\s*Gutenberg', caseSensitive: false),
    RegExp(r'eBook\s*(?:is|was)\s*(?:produced|prepared)', caseSensitive: false),
    RegExp(r"transcriber'?s?\s*note", caseSensitive: false),
    RegExp(r"scanner'?s?\s*note", caseSensitive: false),
    RegExp(r"editor'?s?\s*note", caseSensitive: false),
    RegExp(r'original\s*transcription', caseSensitive: false),
    
    // Copyright / legal
    RegExp(r'copyright\s*[©\u00A9]', caseSensitive: false),
    RegExp(r'all\s*rights\s*reserved', caseSensitive: false),
    RegExp(r'\bISBN\b'),
    RegExp(r'library\s*of\s*congress', caseSensitive: false),
    RegExp(r'published\s*by', caseSensitive: false),
    RegExp(r'printed\s*in', caseSensitive: false),
    
    // Table of contents patterns
    RegExp(r'^contents?\s*$', caseSensitive: false),
    RegExp(r'table\s*of\s*contents', caseSensitive: false),
    RegExp(r'^chapter\s*\d+[.\s]+\w+[.\s]+chapter\s*\d+', caseSensitive: false), // Multiple chapters in one line
    
    // File/technical markers
    RegExp(r'\*{3,}|_{3,}|-{3,}'), // Separator lines
    RegExp(r'^\[.*\]$'), // Editorial notes like [Illustration]
    RegExp(r'^illustration:', caseSensitive: false),
    RegExp(r'^page\s*\d+\s*$', caseSensitive: false), // Page numbers
    
    // Attribution/credits
    RegExp(r'^by\s+[A-Z][a-z]+\s+[A-Z][a-z]+$'), // Author name only
    RegExp(r'^\d{4}$'), // Lone year
    RegExp(r'^[A-Z]{2,}$'), // All caps short text (headers)
  ];

  // Patterns that indicate actual narrative content (high confidence)
  static final _contentPatterns = [
    // Dialogue patterns
    RegExp(r'"[^"]{10,}"'), // Quoted dialogue
    RegExp(r'[""][^""]{10,}[""]'), // Smart quotes dialogue
    RegExp(r'\bsaid\s+\w+\b', caseSensitive: false),
    RegExp(r'\basked\s+\w+\b', caseSensitive: false),
    RegExp(r'\breplied\s+\w+\b', caseSensitive: false),
    
    // Narrative verbs/patterns
    RegExp(r'\bwas\s+(?:sitting|standing|walking|running|looking)', caseSensitive: false),
    RegExp(r'\bhad\s+(?:been|never|always|just)', caseSensitive: false),
    RegExp(r'\bwould\s+(?:have|be|never)', caseSensitive: false),
    
    // Descriptive patterns
    RegExp(r'the\s+(?:sun|moon|sky|sea|wind|rain|night|day|morning|evening)', caseSensitive: false),
    RegExp(r'\bhis\s+(?:eyes|hands|face|heart|mind)\b', caseSensitive: false),
    RegExp(r'\bher\s+(?:eyes|hands|face|heart|mind)\b', caseSensitive: false),
    
    // Story transition patterns
    RegExp(r'\bsuddenly\b', caseSensitive: false),
    RegExp(r'\bfinally\b', caseSensitive: false),
    RegExp(r'\bmeanwhile\b', caseSensitive: false),
    RegExp(r'\bhowever\b', caseSensitive: false),
  ];

  // Patterns that indicate chapter-like structure (medium-high confidence)
  static final _chapterStartPatterns = [
    RegExp(r'^chapter\s*\d+', caseSensitive: false),
    RegExp(r'^chapter\s+[ivxlc]+', caseSensitive: false), // Roman numerals
    RegExp(r'^part\s*\d+', caseSensitive: false),
    RegExp(r'^book\s*\d+', caseSensitive: false),
    RegExp(r'^prologue\b', caseSensitive: false),
    RegExp(r'^epilogue\b', caseSensitive: false),
  ];

  /// Score a single segment's content confidence.
  /// Returns a value between 0.0 and 1.0.
  static double scoreSegment(String text) {
    if (text.isEmpty) return 0.0;
    
    double score = 0.5; // Start at neutral
    
    // Check for boilerplate patterns (reduce confidence)
    int boilerplateMatches = 0;
    for (final pattern in _boilerplatePatterns) {
      if (pattern.hasMatch(text)) {
        boilerplateMatches++;
      }
    }
    score -= boilerplateMatches * 0.15;
    
    // Check for content patterns (increase confidence)
    int contentMatches = 0;
    for (final pattern in _contentPatterns) {
      if (pattern.hasMatch(text)) {
        contentMatches++;
      }
    }
    score += contentMatches * 0.1;
    
    // Chapter starts get medium-high confidence
    for (final pattern in _chapterStartPatterns) {
      if (pattern.hasMatch(text)) {
        score = max(score, 0.6);
        break;
      }
    }
    
    // Text length heuristics
    final wordCount = text.split(RegExp(r'\s+')).length;
    if (wordCount < 5) {
      // Very short segments are suspicious
      score -= 0.2;
    } else if (wordCount > 15) {
      // Longer narrative segments are more likely content
      score += 0.1;
    }
    
    // Sentence structure heuristics
    final sentenceEndCount = RegExp(r'[.!?]').allMatches(text).length;
    if (sentenceEndCount >= 2 && wordCount > 10) {
      // Multiple complete sentences suggest narrative
      score += 0.15;
    }
    
    return score.clamp(0.0, 1.0);
  }

  /// Score all segments in a chapter and return updated segments with confidence.
  static List<Segment> scoreChapterSegments(List<Segment> segments) {
    if (segments.isEmpty) return segments;
    
    return segments.map((segment) {
      final confidence = scoreSegment(segment.text);
      return segment.copyWith(contentConfidence: confidence);
    }).toList();
  }

  /// Find the first segment index with high confidence content in a chapter.
  /// Returns null if no high confidence segment is found.
  static int? findFirstConfidentSegment(List<Segment> segments, {double threshold = 0.6}) {
    for (int i = 0; i < segments.length; i++) {
      final confidence = segments[i].contentConfidence ?? scoreSegment(segments[i].text);
      if (confidence >= threshold) {
        return i;
      }
    }
    return null;
  }

  /// Calculate average confidence for a chapter's segments.
  static double calculateChapterConfidence(List<Segment> segments) {
    if (segments.isEmpty) return 0.5;
    
    double total = 0.0;
    for (final segment in segments) {
      total += segment.contentConfidence ?? scoreSegment(segment.text);
    }
    return total / segments.length;
  }

  /// Determine if a chapter is likely front matter based on segment confidences.
  static bool isLikelyFrontMatter(List<Segment> segments, {double threshold = 0.4}) {
    final avgConfidence = calculateChapterConfidence(segments);
    return avgConfidence < threshold;
  }

  /// Find the first chapter that appears to be actual content.
  /// 
  /// Returns the chapter index (0-indexed) of the first chapter with
  /// high confidence content. Returns 0 if all chapters seem valid.
  static int findFirstContentChapter(
    List<List<Segment>> allChapterSegments, {
    double threshold = 0.5,
  }) {
    for (int chapterIndex = 0; chapterIndex < allChapterSegments.length; chapterIndex++) {
      final segments = allChapterSegments[chapterIndex];
      final avgConfidence = calculateChapterConfidence(segments);
      
      // If this chapter has decent confidence, it's likely where content starts
      if (avgConfidence >= threshold) {
        return chapterIndex;
      }
    }
    return 0; // Default to first chapter
  }
}
