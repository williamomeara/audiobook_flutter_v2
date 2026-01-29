import 'package:core_domain/core_domain.dart';

/// Priority levels for synthesis requests.
///
/// Higher priority requests are processed before lower priority ones.
enum SynthesisPriority {
  /// Highest - segment needed for immediate playback.
  /// Used for current segment and current+1.
  immediate(3),

  /// Normal - lookahead buffer within watermarks.
  /// Used for segments 2-5 ahead.
  prefetch(2),

  /// Lowest - extended prefetch (battery-aware).
  /// Used for segments 6+ ahead when battery allows.
  background(1);

  const SynthesisPriority(this.value);

  /// Numeric value for comparison (higher = more urgent).
  final int value;
}

/// A request to synthesize an audio segment.
///
/// Requests are deduplicated by [cacheKey] and prioritized by [priority].
class SynthesisRequest implements Comparable<SynthesisRequest> {
  SynthesisRequest({
    required this.track,
    required this.voiceId,
    required this.playbackRate,
    required this.segmentIndex,
    required this.priority,
    required this.cacheKey,
    required this.bookId,
    required this.chapterIndex,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// The audio track to synthesize.
  final AudioTrack track;

  /// Voice ID for synthesis.
  final String voiceId;

  /// Playback rate (used for cache key, synthesis always at 1.0 if rate-independent).
  final double playbackRate;

  /// Index of the segment in the current queue.
  final int segmentIndex;

  /// Priority level for this request.
  SynthesisPriority priority;

  /// Cache key for deduplication and result storage.
  final CacheKey cacheKey;

  /// Book ID for cache metadata registration.
  final String bookId;

  /// Chapter index for cache metadata registration.
  final int chapterIndex;

  /// When this request was created (for FIFO within same priority).
  final DateTime createdAt;

  /// Unique key for deduplication (based on cache key).
  String get deduplicationKey => cacheKey.toFilename();

  /// Compare by priority (higher first), then by creation time (older first).
  @override
  int compareTo(SynthesisRequest other) {
    // Higher priority first
    final priorityCompare = other.priority.value.compareTo(priority.value);
    if (priorityCompare != 0) return priorityCompare;

    // Within same priority, older first (FIFO)
    return createdAt.compareTo(other.createdAt);
  }

  /// Upgrade priority if the new priority is higher.
  void upgradePriority(SynthesisPriority newPriority) {
    if (newPriority.value > priority.value) {
      priority = newPriority;
    }
  }

  @override
  String toString() =>
      'SynthesisRequest(book: $bookId, chapter: $chapterIndex, segment: $segmentIndex, priority: ${priority.name}, voice: $voiceId)';
}
