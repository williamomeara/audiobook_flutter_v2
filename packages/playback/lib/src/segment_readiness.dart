import 'dart:async';

/// State of a segment's synthesis readiness.
enum SegmentState {
  /// Not in the prefetch queue yet.
  notQueued,

  /// In the prefetch queue waiting for synthesis.
  queued,

  /// Currently being synthesized.
  synthesizing,

  /// Cached and ready for playback.
  ready,

  /// Synthesis failed.
  error,
}

/// Readiness information for a single segment.
class SegmentReadiness {
  const SegmentReadiness({
    required this.segmentIndex,
    required this.state,
    this.progress,
    this.errorMessage,
  });

  /// Index of this segment within the chapter.
  final int segmentIndex;

  /// Current synthesis state.
  final SegmentState state;

  /// Synthesis progress (0.0-1.0) when state is [SegmentState.synthesizing].
  final double? progress;

  /// Error message when state is [SegmentState.error].
  final String? errorMessage;

  /// Get opacity for UI rendering.
  ///
  /// Ready segments are fully opaque, not-queued segments are greyed out.
  double get opacity {
    switch (state) {
      case SegmentState.ready:
        return 1.0;
      case SegmentState.synthesizing:
        // Interpolate from 0.6 to 1.0 based on progress
        return 0.6 + (progress ?? 0.0) * 0.4;
      case SegmentState.queued:
        return 0.4;
      case SegmentState.notQueued:
        return 0.3;
      case SegmentState.error:
        return 1.0; // Full opacity but with error styling
    }
  }

  /// Create a ready state.
  factory SegmentReadiness.ready(int segmentIndex) {
    return SegmentReadiness(
      segmentIndex: segmentIndex,
      state: SegmentState.ready,
    );
  }

  /// Create a queued state.
  factory SegmentReadiness.queued(int segmentIndex) {
    return SegmentReadiness(
      segmentIndex: segmentIndex,
      state: SegmentState.queued,
    );
  }

  /// Create a synthesizing state with progress.
  factory SegmentReadiness.synthesizing(int segmentIndex, {double? progress}) {
    return SegmentReadiness(
      segmentIndex: segmentIndex,
      state: SegmentState.synthesizing,
      progress: progress ?? 0.0,
    );
  }

  /// Create an error state.
  factory SegmentReadiness.error(int segmentIndex, String message) {
    return SegmentReadiness(
      segmentIndex: segmentIndex,
      state: SegmentState.error,
      errorMessage: message,
    );
  }

  @override
  String toString() =>
      'SegmentReadiness($segmentIndex: $state, opacity: ${opacity.toStringAsFixed(2)})';
}

/// Event types for segment readiness changes.
sealed class SegmentReadinessEvent {
  const SegmentReadinessEvent(this.segmentIndex);
  final int segmentIndex;
}

class SynthesisStartedEvent extends SegmentReadinessEvent {
  const SynthesisStartedEvent(super.segmentIndex);
}

class SynthesisProgressEvent extends SegmentReadinessEvent {
  const SynthesisProgressEvent(super.segmentIndex, this.progress);
  final double progress;
}

class SynthesisCompleteEvent extends SegmentReadinessEvent {
  const SynthesisCompleteEvent(super.segmentIndex);
}

class SynthesisErrorEvent extends SegmentReadinessEvent {
  const SynthesisErrorEvent(super.segmentIndex, this.message);
  final String message;
}

class SegmentQueuedEvent extends SegmentReadinessEvent {
  const SegmentQueuedEvent(super.segmentIndex);
}

/// Tracks synthesis readiness for all segments in a chapter.
///
/// This class is the source of truth for segment readiness state,
/// which can be consumed by the UI to show opacity-based feedback.
class SegmentReadinessTracker {
  SegmentReadinessTracker({
    required this.bookId,
    required this.chapterIndex,
    required this.totalSegments,
  });

  /// Book this tracker belongs to.
  final String bookId;

  /// Chapter index within the book.
  final int chapterIndex;

  /// Total number of segments in this chapter.
  final int totalSegments;

  /// Readiness state for each segment.
  final Map<int, SegmentReadiness> _readiness = {};

  /// Stream controller for readiness changes.
  final _controller = StreamController<Map<int, SegmentReadiness>>.broadcast();

  /// Stream of readiness state changes.
  Stream<Map<int, SegmentReadiness>> get stream => _controller.stream;

  /// Get current readiness map.
  Map<int, SegmentReadiness> get readiness => Map.unmodifiable(_readiness);

  /// Get readiness for a specific segment.
  SegmentReadiness? getForSegment(int index) => _readiness[index];

  /// Get opacity for a specific segment.
  double opacityForSegment(int index) {
    return _readiness[index]?.opacity ?? 0.3;
  }

  /// Initialize from cached segments.
  void initializeFromCache(List<int> cachedSegmentIndices) {
    for (final index in cachedSegmentIndices) {
      _readiness[index] = SegmentReadiness.ready(index);
    }
    _notifyListeners();
  }

  /// Called when synthesis starts for a segment.
  void onSynthesisStarted(int segmentIndex) {
    _readiness[segmentIndex] = SegmentReadiness.synthesizing(segmentIndex);
    _notifyListeners();
  }

  /// Called with synthesis progress updates.
  void onSynthesisProgress(int segmentIndex, double progress) {
    if (_readiness[segmentIndex]?.state != SegmentState.synthesizing) return;

    _readiness[segmentIndex] = SegmentReadiness.synthesizing(
      segmentIndex,
      progress: progress,
    );
    _notifyListeners();
  }

  /// Called when synthesis completes successfully.
  void onSynthesisComplete(int segmentIndex) {
    _readiness[segmentIndex] = SegmentReadiness.ready(segmentIndex);
    _notifyListeners();
  }

  /// Called when synthesis fails.
  void onSynthesisError(int segmentIndex, String message) {
    _readiness[segmentIndex] = SegmentReadiness.error(segmentIndex, message);
    _notifyListeners();
  }

  /// Called when segment is added to prefetch queue.
  void onSegmentQueued(int segmentIndex) {
    // Don't downgrade if already ready or synthesizing
    final current = _readiness[segmentIndex];
    if (current?.state == SegmentState.ready ||
        current?.state == SegmentState.synthesizing) {
      return;
    }

    _readiness[segmentIndex] = SegmentReadiness.queued(segmentIndex);
    _notifyListeners();
  }

  /// Batch update for multiple segments being queued.
  void onSegmentsQueued(Iterable<int> segmentIndices) {
    var changed = false;
    for (final index in segmentIndices) {
      final current = _readiness[index];
      if (current?.state != SegmentState.ready &&
          current?.state != SegmentState.synthesizing) {
        _readiness[index] = SegmentReadiness.queued(index);
        changed = true;
      }
    }
    if (changed) {
      _notifyListeners();
    }
  }

  /// Reset all readiness state.
  void reset() {
    _readiness.clear();
    _notifyListeners();
  }

  /// Count of ready segments.
  int get readyCount =>
      _readiness.values.where((r) => r.state == SegmentState.ready).length;

  /// Count of segments currently synthesizing.
  int get synthesizingCount =>
      _readiness.values.where((r) => r.state == SegmentState.synthesizing).length;

  /// Count of queued segments.
  int get queuedCount =>
      _readiness.values.where((r) => r.state == SegmentState.queued).length;

  /// Overall completion percentage (0.0-1.0).
  double get completionPercent {
    if (totalSegments <= 0) return 0.0;
    return readyCount / totalSegments;
  }

  void _notifyListeners() {
    if (!_controller.isClosed) {
      _controller.add(Map.unmodifiable(_readiness));
    }
  }

  /// Dispose resources.
  void dispose() {
    _controller.close();
  }
}
