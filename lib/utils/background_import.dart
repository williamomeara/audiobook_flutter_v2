import 'dart:isolate';
import 'package:core_domain/core_domain.dart';

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
  });

  final List<List<SegmentData>> chapterSegments;
}

/// Serializable segment data for isolate communication.
class SegmentData {
  const SegmentData({
    required this.text,
    required this.index,
    required this.estimatedDurationMs,
    this.segmentType = SegmentType.text,
    this.metadata,
  });

  final String text;
  final int index;
  final int estimatedDurationMs;
  final SegmentType segmentType;
  final Map<String, dynamic>? metadata;

  /// Convert to Segment model.
  Segment toSegment() => Segment(
    text: text,
    index: index,
    estimatedDurationMs: estimatedDurationMs,
    type: segmentType,
    metadata: metadata,
  );
}

/// Run segmentation in a background isolate.
/// 
/// This moves CPU-intensive text segmentation off the main UI thread
/// to prevent jank during book import.
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
      segmentType: s.type,
      metadata: s.metadata,
    )).toList();
    
    allChapterSegments.add(segmentsWithMetadata);
  }

  return SegmentationResult(
    chapterSegments: allChapterSegments,
  );
}
