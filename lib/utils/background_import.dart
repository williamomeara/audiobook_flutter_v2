import 'dart:isolate';
import 'package:core_domain/core_domain.dart';

import 'segment_confidence_scorer.dart';

/// Parameters for background segmentation work.
class SegmentationParams {
  const SegmentationParams({
    required this.chapters,
  });

  final List<ChapterData> chapters;
}

/// Serializable chapter data for isolate communication.
class ChapterData {
  const ChapterData({
    required this.index,
    required this.content,
  });

  final int index;
  final String content;
}

/// Result of background segmentation.
class SegmentationResult {
  const SegmentationResult({
    required this.chapterSegments,
    required this.firstContentChapter,
  });

  final List<List<SegmentData>> chapterSegments;
  final int firstContentChapter;
}

/// Serializable segment data for isolate communication.
class SegmentData {
  const SegmentData({
    required this.text,
    required this.index,
    required this.estimatedDurationMs,
    required this.contentConfidence,
  });

  final String text;
  final int index;
  final int estimatedDurationMs;
  final double contentConfidence;

  /// Convert to Segment model.
  Segment toSegment() => Segment(
    text: text,
    index: index,
    estimatedDurationMs: estimatedDurationMs,
    contentConfidence: contentConfidence,
  );
}

/// Run segmentation and scoring in a background isolate.
/// 
/// This moves CPU-intensive text segmentation and confidence scoring
/// off the main UI thread to prevent jank during book import.
Future<SegmentationResult> runSegmentationInBackground(
  List<Chapter> chapters,
) async {
  final chapterData = chapters.map((ch) => ChapterData(
    index: ch.number,
    content: ch.content,
  )).toList();

  return Isolate.run(() => _segmentChapters(SegmentationParams(
    chapters: chapterData,
  )));
}

/// Internal isolate function - runs in background.
SegmentationResult _segmentChapters(SegmentationParams params) {
  final allChapterSegments = <List<SegmentData>>[];

  for (final chapter in params.chapters) {
    final rawSegments = segmentText(chapter.content);
    
    final segmentsWithMetadata = rawSegments.map((s) => SegmentData(
      text: s.text,
      index: s.index,
      estimatedDurationMs: estimateDurationMs(s.text),
      contentConfidence: SegmentConfidenceScorer.scoreSegment(s.text),
    )).toList();
    
    allChapterSegments.add(segmentsWithMetadata);
  }

  // Convert to list of lists of Segment for scoring
  final segmentsForScoring = allChapterSegments.map((chapterSegs) =>
    chapterSegs.map((s) => Segment(
      text: s.text,
      index: s.index,
      estimatedDurationMs: s.estimatedDurationMs,
      contentConfidence: s.contentConfidence,
    )).toList()
  ).toList();

  final firstContentChapter = SegmentConfidenceScorer.findFirstContentChapter(
    segmentsForScoring,
    threshold: 0.5,
  );

  return SegmentationResult(
    chapterSegments: allChapterSegments,
    firstContentChapter: firstContentChapter,
  );
}
