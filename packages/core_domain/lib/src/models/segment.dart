/// Marker prefix for figure placeholders in text.
/// Format: [FIGURE:{imagePath}:{altText}]
const String figurePlaceholderPrefix = '[FIGURE:';
const String figurePlaceholderSuffix = ']';

/// Classifies the type of content in a segment.
/// 
/// Used for type-aware rendering and optional TTS skip behavior.
enum SegmentType {
  /// Normal prose text.
  text,
  
  /// Code block - render with monospace font, syntax highlighting.
  /// Can be skipped during TTS playback.
  code,
  
  /// Image/figure reference - placeholder for visual content.
  /// Always skipped during TTS (no audio for images).
  figure,
  
  /// Table data - render as structured table or collapsed card.
  /// Can be skipped during TTS playback.
  table,
  
  /// Section or chapter heading.
  heading,
  
  /// Block quote - render with italic/indented styling.
  quote,
}

/// Represents a segment of text to be synthesized and played.
///
/// A segment is typically a sentence or small paragraph that forms
/// a single unit of synthesis.
class Segment {
  const Segment({
    required this.text,
    required this.index,
    this.estimatedDurationMs,
    this.type = SegmentType.text,
    this.metadata,
  });

  /// The text content of this segment.
  final String text;

  /// Index within the chapter (0-indexed).
  final int index;

  /// Estimated playback duration in milliseconds (at 1.0x speed).
  final int? estimatedDurationMs;
  
  /// The type of content in this segment.
  final SegmentType type;
  
  /// Optional metadata for the segment (e.g., language for code, image path for figures).
  final Map<String, dynamic>? metadata;

  /// Estimated duration in Duration format.
  Duration get estimatedDuration =>
      Duration(milliseconds: estimatedDurationMs ?? _estimateMs(text));

  /// Rough estimate: 150 WPM, average 5 chars per word.
  static int _estimateMs(String text) => (text.length / 5 * 400).round();
  
  /// Whether this segment should be skipped during TTS playback by default.
  bool get shouldSkipByDefault => type == SegmentType.figure;
  
  /// Whether this segment type can optionally be skipped (user setting).
  bool get canBeSkipped => type == SegmentType.code || type == SegmentType.table || type == SegmentType.figure;

  Segment copyWith({
    String? text,
    int? index,
    int? estimatedDurationMs,
    SegmentType? type,
    Map<String, dynamic>? metadata,
  }) {
    return Segment(
      text: text ?? this.text,
      index: index ?? this.index,
      estimatedDurationMs: estimatedDurationMs ?? this.estimatedDurationMs,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Segment &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          index == other.index &&
          type == other.type;

  @override
  int get hashCode => Object.hash(text, index, type);

  @override
  String toString() =>
      'Segment(index: $index, type: $type, text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}")';
}

/// Represents an audio track in the playback queue.
///
/// An audio track corresponds to a segment with additional metadata
/// for playback management.
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.text,
    required this.chapterIndex,
    required this.segmentIndex,
    this.title,
    this.bookId,
    this.chapterId,
    this.estimatedDuration,
    this.segmentType = SegmentType.text,
    this.metadata,
  });

  /// Unique track identifier (e.g., "bookId-chapterIndex-segmentIndex").
  final String id;

  /// Text content to synthesize.
  final String text;

  /// Display title (typically chapter title).
  final String? title;

  /// Parent book ID.
  final String? bookId;

  /// Parent chapter ID.
  final String? chapterId;

  /// Chapter index (0-indexed).
  final int chapterIndex;

  /// Segment index within the chapter (0-indexed).
  final int segmentIndex;

  /// Estimated duration for buffering calculations.
  final Duration? estimatedDuration;
  
  /// The type of content in this segment.
  final SegmentType segmentType;
  
  /// Optional metadata (e.g., language for code, caption for figures).
  final Map<String, dynamic>? metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrack && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'AudioTrack(id: $id, chapter: $chapterIndex, segment: $segmentIndex)';
}
