import 'dart:async';

/// Callback for getting current buffer in seconds.
typedef BufferGetter = double Function();

/// Provides optional "wait for buffer" functionality.
///
/// This is an OPT-IN feature. Users can choose to wait for buffer
/// to build before playing, but they can ALWAYS:
/// - Cancel and play immediately at any time
/// - Start playing even with zero buffer
/// - Dismiss any suggestions to wait
///
/// **Philosophy: User Choice, Not Forced Waiting**
///
/// This class provides the option to wait for buffer, but never
/// blocks or forces the user to wait.
///
/// ## Usage
///
/// ```dart
/// final buffering = OptionalBuffering(
///   bufferGetter: () => scheduler.estimateBufferedAheadMs() / 1000.0,
///   targetBufferSeconds: 120.0, // 2 minutes
/// );
///
/// // User tapped "Wait for buffer"
/// buffering.startWaiting(
///   onProgress: (status) => updateUI(status),
///   onReady: () => showReadyToPlay(),
/// );
///
/// // User can cancel anytime
/// buffering.cancel(); // Returns to normal playback
/// ```
class OptionalBuffering {
  /// Function to get current buffer ahead (in seconds).
  final BufferGetter bufferGetter;

  /// Target buffer to wait for (in seconds).
  final double targetBufferSeconds;

  /// How often to check buffer progress.
  final Duration checkInterval;

  Timer? _checkTimer;
  Completer<void>? _waitCompleter;
  void Function(BufferWaitProgress)? _onProgress;

  /// Creates an OptionalBuffering instance.
  ///
  /// [bufferGetter] returns seconds of audio buffered ahead.
  /// [targetBufferSeconds] is the buffer target (default 120s = 2 min).
  /// [checkInterval] controls check frequency (default 500ms).
  OptionalBuffering({
    required this.bufferGetter,
    this.targetBufferSeconds = 120.0,
    this.checkInterval = const Duration(milliseconds: 500),
  });

  /// Whether currently waiting for buffer.
  bool get isWaiting => _checkTimer != null;

  /// Start waiting for buffer to reach target.
  ///
  /// [onProgress] is called with buffer progress updates.
  /// [onReady] is called when buffer reaches target.
  ///
  /// Returns a Future that completes when buffer reaches target,
  /// or is cancelled by calling [cancel] or [playNow].
  ///
  /// **User can always cancel or play immediately.**
  Future<BufferWaitResult> startWaiting({
    void Function(BufferWaitProgress)? onProgress,
    void Function()? onReady,
  }) async {
    if (isWaiting) {
      return BufferWaitResult.alreadyWaiting;
    }

    _onProgress = onProgress;
    _waitCompleter = Completer<void>();

    // Emit initial progress
    _emitProgress();

    // Start checking buffer
    _checkTimer = Timer.periodic(checkInterval, (_) {
      _emitProgress();

      final buffer = bufferGetter();
      if (buffer >= targetBufferSeconds) {
        _complete(onReady);
      }
    });

    // Wait for completion (or cancellation)
    try {
      await _waitCompleter!.future;
      return BufferWaitResult.bufferReached;
    } catch (_) {
      return BufferWaitResult.cancelled;
    }
  }

  /// Cancel waiting and let user play immediately.
  ///
  /// **User can always cancel waiting.**
  void cancel() {
    if (_waitCompleter != null && !_waitCompleter!.isCompleted) {
      _waitCompleter!.completeError(BufferWaitCancelled());
    }
    _cleanup();
  }

  /// Same as cancel - user chose to play now.
  ///
  /// **User can always play immediately.**
  void playNow() => cancel();

  void _complete(void Function()? onReady) {
    _waitCompleter?.complete();
    _cleanup();
    onReady?.call();
  }

  void _cleanup() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _onProgress = null;
  }

  void _emitProgress() {
    final buffer = bufferGetter();
    final progress = BufferWaitProgress(
      currentBuffer: buffer,
      targetBuffer: targetBufferSeconds,
      timestamp: DateTime.now(),
    );
    _onProgress?.call(progress);
  }

  /// Dispose resources.
  void dispose() {
    cancel();
  }
}

/// Progress update while waiting for buffer.
class BufferWaitProgress {
  /// Current buffer in seconds.
  final double currentBuffer;

  /// Target buffer in seconds.
  final double targetBuffer;

  /// Timestamp of this update.
  final DateTime timestamp;

  const BufferWaitProgress({
    required this.currentBuffer,
    required this.targetBuffer,
    required this.timestamp,
  });

  /// Progress as a value from 0.0 to 1.0.
  double get progress => (currentBuffer / targetBuffer).clamp(0.0, 1.0);

  /// Progress as a percentage (0-100).
  int get progressPercent => (progress * 100).round();

  /// Whether target has been reached.
  bool get isComplete => currentBuffer >= targetBuffer;

  /// User-friendly progress text.
  String get displayText {
    final current = currentBuffer.round();
    final target = targetBuffer.round();
    return '${current}s / ${target}s';
  }

  /// User-friendly time remaining estimate.
  /// Assumes buffer grows at roughly 1:1 with real time.
  String get estimatedTimeRemaining {
    final remaining = (targetBuffer - currentBuffer).clamp(0.0, targetBuffer);
    if (remaining < 60) {
      return '~${remaining.round()}s';
    }
    final mins = (remaining / 60).ceil();
    return '~${mins}m';
  }
}

/// Result of waiting for buffer.
enum BufferWaitResult {
  /// Buffer reached target.
  bufferReached,

  /// User cancelled waiting.
  cancelled,

  /// Already waiting (startWaiting called twice).
  alreadyWaiting,
}

/// Exception thrown when buffer wait is cancelled.
class BufferWaitCancelled implements Exception {
  @override
  String toString() => 'Buffer wait cancelled by user';
}
