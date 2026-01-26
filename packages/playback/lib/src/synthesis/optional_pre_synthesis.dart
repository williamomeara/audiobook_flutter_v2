import 'dart:async';

/// Callback for synthesis of a single segment.
typedef SegmentSynthesizer = Future<void> Function(int segmentIndex);

/// Callback for progress updates during pre-synthesis.
typedef PreSynthesisProgressCallback = void Function(PreSynthesisProgress);

/// Provides OPTIONAL pre-synthesis functionality.
///
/// Pre-synthesis is a convenience feature for users who want guaranteed
/// smooth playback. It synthesizes an entire chapter in the background
/// before or during playback.
///
/// **Philosophy: User Choice, Not Forced**
///
/// - Pre-synthesis is NEVER required
/// - Users can ALWAYS play immediately without pre-synthesis
/// - Users can cancel pre-synthesis at any time
/// - Pre-synthesis runs at low priority (doesn't interfere with playback)
///
/// ## Usage
///
/// ```dart
/// final preSynth = OptionalPreSynthesis(
///   segmentSynthesizer: (index) => coordinator.synthesizeSegment(index),
/// );
///
/// // User chose to pre-synthesize chapter (optional)
/// final result = await preSynth.preSynthesizeChapter(
///   bookId: 'book123',
///   chapterIndex: 5,
///   totalSegments: 42,
///   onProgress: (progress) => updateUI(progress),
/// );
///
/// // User can cancel anytime
/// preSynth.cancel('book123', 5);
///
/// // User can play at any time, even while pre-synthesis is running
/// player.play(); // Never blocked by pre-synthesis
/// ```
class OptionalPreSynthesis {
  /// Function to synthesize a single segment.
  final SegmentSynthesizer segmentSynthesizer;

  /// Maximum concurrent synthesis during pre-synthesis.
  /// Lower than normal to not interfere with playback.
  final int maxConcurrency;

  final Map<String, _PreSynthesisJob> _activeJobs = {};

  /// Creates an OptionalPreSynthesis instance.
  ///
  /// [segmentSynthesizer] synthesizes a single segment by index.
  /// [maxConcurrency] limits parallel synthesis (default 1 for low priority).
  OptionalPreSynthesis({
    required this.segmentSynthesizer,
    this.maxConcurrency = 1,
  });

  /// Start pre-synthesizing a chapter in the background.
  ///
  /// This is OPTIONAL - user can play immediately without waiting.
  ///
  /// [bookId] identifies the book.
  /// [chapterIndex] identifies the chapter.
  /// [totalSegments] is the number of segments in the chapter.
  /// [onProgress] receives progress updates.
  /// [startSegment] allows resuming from a specific segment.
  ///
  /// Returns result when complete, cancelled, or errored.
  Future<PreSynthesisResult> preSynthesizeChapter({
    required String bookId,
    required int chapterIndex,
    required int totalSegments,
    PreSynthesisProgressCallback? onProgress,
    int startSegment = 0,
  }) async {
    final jobKey = _jobKey(bookId, chapterIndex);

    // Check if already running
    if (_activeJobs.containsKey(jobKey)) {
      return PreSynthesisResult.alreadyRunning;
    }

    // Create job
    final job = _PreSynthesisJob(
      bookId: bookId,
      chapterIndex: chapterIndex,
      totalSegments: totalSegments,
      currentSegment: startSegment,
      onProgress: onProgress,
    );
    _activeJobs[jobKey] = job;

    try {
      // Synthesize segments sequentially (low priority)
      for (var i = startSegment; i < totalSegments && !job.isCancelled; i++) {
        job.currentSegment = i;
        _emitProgress(job);

        await segmentSynthesizer(i);

        job.completedSegments++;
      }

      if (job.isCancelled) {
        return PreSynthesisResult.cancelled;
      }

      job.isComplete = true;
      _emitProgress(job);
      return PreSynthesisResult.complete;
    } catch (e) {
      job.error = e.toString();
      return PreSynthesisResult.error;
    } finally {
      _activeJobs.remove(jobKey);
    }
  }

  /// Cancel pre-synthesis for a chapter.
  ///
  /// **User can always cancel pre-synthesis.**
  void cancel(String bookId, int chapterIndex) {
    final jobKey = _jobKey(bookId, chapterIndex);
    _activeJobs[jobKey]?.cancel();
  }

  /// Cancel all active pre-synthesis jobs.
  void cancelAll() {
    for (final job in _activeJobs.values) {
      job.cancel();
    }
  }

  /// Check if chapter is being pre-synthesized.
  bool isRunning(String bookId, int chapterIndex) {
    return _activeJobs.containsKey(_jobKey(bookId, chapterIndex));
  }

  /// Get progress for a chapter pre-synthesis.
  PreSynthesisProgress? getProgress(String bookId, int chapterIndex) {
    final job = _activeJobs[_jobKey(bookId, chapterIndex)];
    return job != null ? _buildProgress(job) : null;
  }

  String _jobKey(String bookId, int chapterIndex) => '$bookId:$chapterIndex';

  void _emitProgress(_PreSynthesisJob job) {
    job.onProgress?.call(_buildProgress(job));
  }

  PreSynthesisProgress _buildProgress(_PreSynthesisJob job) {
    return PreSynthesisProgress(
      bookId: job.bookId,
      chapterIndex: job.chapterIndex,
      currentSegment: job.currentSegment,
      totalSegments: job.totalSegments,
      completedSegments: job.completedSegments,
      isComplete: job.isComplete,
      isCancelled: job.isCancelled,
      error: job.error,
    );
  }

  /// Dispose resources.
  void dispose() {
    cancelAll();
  }
}

/// Internal job tracking for pre-synthesis.
class _PreSynthesisJob {
  final String bookId;
  final int chapterIndex;
  final int totalSegments;
  final PreSynthesisProgressCallback? onProgress;

  int currentSegment;
  int completedSegments = 0;
  bool isComplete = false;
  bool isCancelled = false;
  String? error;

  _PreSynthesisJob({
    required this.bookId,
    required this.chapterIndex,
    required this.totalSegments,
    required this.currentSegment,
    this.onProgress,
  });

  void cancel() {
    isCancelled = true;
  }
}

/// Progress update during pre-synthesis.
class PreSynthesisProgress {
  /// Book identifier.
  final String bookId;

  /// Chapter being synthesized.
  final int chapterIndex;

  /// Current segment being synthesized.
  final int currentSegment;

  /// Total segments in chapter.
  final int totalSegments;

  /// Number of completed segments.
  final int completedSegments;

  /// Whether synthesis is complete.
  final bool isComplete;

  /// Whether synthesis was cancelled.
  final bool isCancelled;

  /// Error message if failed.
  final String? error;

  const PreSynthesisProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.currentSegment,
    required this.totalSegments,
    required this.completedSegments,
    required this.isComplete,
    required this.isCancelled,
    this.error,
  });

  /// Progress as a value from 0.0 to 1.0.
  double get progress =>
      totalSegments > 0 ? completedSegments / totalSegments : 0.0;

  /// Progress as a percentage (0-100).
  int get progressPercent => (progress * 100).round();

  /// User-friendly progress text.
  String get displayText {
    if (isComplete) return 'Complete';
    if (isCancelled) return 'Cancelled';
    if (error != null) return 'Error';
    return '$completedSegments / $totalSegments segments';
  }

  /// Whether pre-synthesis is still active.
  bool get isActive => !isComplete && !isCancelled && error == null;
}

/// Result of pre-synthesis operation.
enum PreSynthesisResult {
  /// Chapter was fully pre-synthesized.
  complete,

  /// User cancelled pre-synthesis.
  cancelled,

  /// Pre-synthesis was already running for this chapter.
  alreadyRunning,

  /// An error occurred during synthesis.
  error,
}

/// Estimates for pre-synthesis time and storage.
class PreSynthesisEstimate {
  /// Estimated time to complete pre-synthesis.
  final Duration estimatedTime;

  /// Estimated storage required (in bytes).
  final int estimatedStorageBytes;

  /// Number of segments to synthesize.
  final int segmentCount;

  const PreSynthesisEstimate({
    required this.estimatedTime,
    required this.estimatedStorageBytes,
    required this.segmentCount,
  });

  /// User-friendly time estimate.
  String get timeDisplayText {
    final minutes = estimatedTime.inMinutes;
    if (minutes < 1) return 'Less than a minute';
    if (minutes == 1) return '~1 minute';
    return '~$minutes minutes';
  }

  /// User-friendly storage estimate.
  String get storageDisplayText {
    final mb = estimatedStorageBytes / (1024 * 1024);
    if (mb < 1) return 'Less than 1 MB';
    if (mb < 10) return '~${mb.toStringAsFixed(1)} MB';
    return '~${mb.round()} MB';
  }

  /// Create estimate based on segment count and RTF.
  ///
  /// [segmentCount] is the number of segments.
  /// [avgSegmentDurationSeconds] is average audio duration per segment.
  /// [rtf] is the Real-Time Factor (synthesis time / audio time).
  factory PreSynthesisEstimate.fromRTF({
    required int segmentCount,
    required double avgSegmentDurationSeconds,
    required double rtf,
    int bytesPerSecondAudio = 16000, // ~16KB/s for typical audio
  }) {
    final totalAudioSeconds = segmentCount * avgSegmentDurationSeconds;
    final synthesisSeconds = totalAudioSeconds * rtf;
    final storageBytes = (totalAudioSeconds * bytesPerSecondAudio).round();

    return PreSynthesisEstimate(
      estimatedTime: Duration(seconds: synthesisSeconds.round()),
      estimatedStorageBytes: storageBytes,
      segmentCount: segmentCount,
    );
  }
}
