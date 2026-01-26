import 'dart:async';

import 'buffer_status.dart';

/// Callback for providing buffer estimation.
typedef BufferEstimator = double Function();

/// Callback for checking if synthesis is active.
typedef SynthesisChecker = bool Function();

/// Callback for getting active synthesis count.
typedef ActiveSynthesisCounter = int Function();

/// Provides real-time buffer status for UI display.
///
/// This class bridges the synthesis system to the UI layer, providing
/// a stream of [BufferStatus] updates that the UI can display.
///
/// **Philosophy: Inform, Don't Block**
///
/// This class is purely informational. It tells the user about buffer
/// status but never blocks playback or forces waiting.
///
/// ## Usage
///
/// ```dart
/// final bufferAware = BufferAwarePlayback(
///   bufferEstimator: () => scheduler.estimateBufferedAheadMs() / 1000.0,
///   synthesisChecker: () => coordinator.isAnySynthesisActive,
///   activeSynthesisCounter: () => coordinator.activeSynthesisCount,
///   playbackRateGetter: () => playerState.playbackRate,
/// );
///
/// bufferAware.start();
///
/// // In UI:
/// StreamBuilder<BufferStatus>(
///   stream: bufferAware.statusStream,
///   builder: (context, snapshot) {
///     final status = snapshot.data ?? BufferStatus.empty;
///     return BufferIndicator(status: status);
///   },
/// );
/// ```
class BufferAwarePlayback {
  /// Function to get current buffer ahead (in seconds).
  final BufferEstimator bufferEstimator;

  /// Function to check if synthesis is active.
  final SynthesisChecker synthesisChecker;

  /// Function to get number of active synthesis operations.
  final ActiveSynthesisCounter activeSynthesisCounter;

  /// Function to get current playback rate.
  final double Function() playbackRateGetter;

  /// How often to update buffer status.
  final Duration updateInterval;

  final StreamController<BufferStatus> _statusController =
      StreamController<BufferStatus>.broadcast();

  Timer? _updateTimer;
  BufferStatus _lastStatus = BufferStatus.empty;

  /// Creates a BufferAwarePlayback instance.
  ///
  /// [bufferEstimator] returns seconds of audio buffered ahead.
  /// [synthesisChecker] returns true if synthesis is currently active.
  /// [activeSynthesisCounter] returns count of concurrent synthesis ops.
  /// [playbackRateGetter] returns current playback rate.
  /// [updateInterval] controls update frequency (default 500ms).
  BufferAwarePlayback({
    required this.bufferEstimator,
    required this.synthesisChecker,
    required this.activeSynthesisCounter,
    required this.playbackRateGetter,
    this.updateInterval = const Duration(milliseconds: 500),
  });

  /// Stream of buffer status updates.
  Stream<BufferStatus> get statusStream => _statusController.stream;

  /// Most recent buffer status.
  BufferStatus get currentStatus => _lastStatus;

  /// Whether status updates are active.
  bool get isActive => _updateTimer != null;

  /// Start emitting buffer status updates.
  void start() {
    if (_updateTimer != null) return;

    // Emit initial status
    _emitStatus();

    // Set up periodic updates
    _updateTimer = Timer.periodic(updateInterval, (_) => _emitStatus());
  }

  /// Stop emitting buffer status updates.
  void stop() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  /// Manually trigger a status update (e.g., after seek).
  void refresh() {
    _emitStatus();
  }

  void _emitStatus() {
    final status = BufferStatus(
      bufferSeconds: bufferEstimator(),
      playbackRate: playbackRateGetter(),
      isSynthesizing: synthesisChecker(),
      activeSynthesisCount: activeSynthesisCounter(),
      timestamp: DateTime.now(),
    );

    _lastStatus = status;
    _statusController.add(status);
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _statusController.close();
  }
}

/// Configuration for buffer status display.
class BufferDisplayConfig {
  /// Whether to show buffer indicator in player UI.
  final bool showBufferIndicator;

  /// Whether to show low buffer warnings (dismissible toasts).
  final bool showLowBufferWarnings;

  /// Threshold for low buffer warning (in seconds).
  final double lowBufferThreshold;

  /// Threshold for critical buffer warning (in seconds).
  final double criticalBufferThreshold;

  const BufferDisplayConfig({
    this.showBufferIndicator = true,
    this.showLowBufferWarnings = true,
    this.lowBufferThreshold = 10.0,
    this.criticalBufferThreshold = 3.0,
  });

  /// Default configuration.
  static const defaults = BufferDisplayConfig();

  /// Minimal configuration (just show buffer level, no warnings).
  static const minimal = BufferDisplayConfig(
    showLowBufferWarnings: false,
  );
}
