/// Represents a segment of text to be synthesized and played.
///
/// A segment is typically a sentence or small paragraph that forms
/// a single unit of synthesis.
class Segment {
  const Segment({
    required this.text,
    required this.index,
    this.estimatedDurationMs,
  });

  /// The text content of this segment.
  final String text;

  /// Index within the chapter (0-indexed).
  final int index;

  /// Estimated playback duration in milliseconds (at 1.0x speed).
  final int? estimatedDurationMs;

  /// Estimated duration in Duration format.
  Duration get estimatedDuration =>
      Duration(milliseconds: estimatedDurationMs ?? _estimateMs(text));

  /// Rough estimate: 150 WPM, average 5 chars per word.
  static int _estimateMs(String text) => (text.length / 5 * 400).round();

  Segment copyWith({
    String? text,
    int? index,
    int? estimatedDurationMs,
  }) {
    return Segment(
      text: text ?? this.text,
      index: index ?? this.index,
      estimatedDurationMs: estimatedDurationMs ?? this.estimatedDurationMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Segment &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          index == other.index;

  @override
  int get hashCode => Object.hash(text, index);

  @override
  String toString() =>
      'Segment(index: $index, text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}")';
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
