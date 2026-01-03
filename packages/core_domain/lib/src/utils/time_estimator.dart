/// Estimates audio duration from text content.
///
/// These estimates are used for buffer management and prefetch decisions.
class TimeEstimator {
  TimeEstimator._();

  /// Average words per minute for TTS at 1.0x speed.
  static const int wordsPerMinute = 150;

  /// Average characters per word (including spaces).
  static const double charsPerWord = 5.0;

  /// Estimate duration in milliseconds for given text at specified rate.
  static int estimateDurationMs(String text, {double playbackRate = 1.0}) {
    if (text.isEmpty) return 0;

    final wordCount = text.length / charsPerWord;
    final minutesAt1x = wordCount / wordsPerMinute;
    final effectiveMinutes = minutesAt1x / playbackRate;

    return (effectiveMinutes * 60 * 1000).round();
  }

  /// Estimate total duration for a list of text segments.
  static int estimateTotalDurationMs(
    List<String> segments, {
    double playbackRate = 1.0,
  }) {
    return segments.fold<int>(
      0,
      (sum, text) => sum + estimateDurationMs(text, playbackRate: playbackRate),
    );
  }

  /// Format duration for display (e.g., "2:34" or "1:23:45").
  static String formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).round();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

/// Convenience function for estimating duration.
int estimateDurationMs(String text, {double playbackRate = 1.0}) {
  return TimeEstimator.estimateDurationMs(text, playbackRate: playbackRate);
}
