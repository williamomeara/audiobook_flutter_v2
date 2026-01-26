import 'dart:async';

import 'package:logging/logging.dart';

import 'buffer_gauge.dart';
import 'concurrency_governor.dart';
import 'demand_controller.dart';
import 'demand_signal.dart';
import 'device_capabilities.dart';
import 'dynamic_semaphore.dart';
import 'rtf_monitor.dart';

final _logger = Logger('AutoCalibration');

/// Callback for getting current buffer ahead in milliseconds.
typedef BufferAheadCallback = int Function();

/// Callback for getting current playback rate.
typedef PlaybackRateCallback = double Function();

/// Callback for checking if playback is active.
typedef IsPlayingCallback = bool Function();

/// Manages the auto-calibration system for synthesis.
///
/// This class orchestrates:
/// - [BufferGauge] for monitoring buffer status
/// - [DemandController] for demand-based concurrency decisions
/// - [ConcurrencyGovernor] for adjusting semaphore slots
/// - [RTFMonitor] for tracking synthesis performance
///
/// ## Usage
///
/// ```dart
/// final manager = AutoCalibrationManager(
///   engineSemaphores: coordinator.engineSemaphores,
///   getBufferAheadMs: () => scheduler.estimateBufferedAheadMs(...),
///   getPlaybackRate: () => state.playbackRate,
///   isPlaying: () => state.isPlaying,
/// );
///
/// await manager.initialize();
/// manager.start();
///
/// // Record synthesis completions
/// coordinator.onSegmentReady.listen((event) {
///   if (!event.wasFromCache) {
///     manager.recordSynthesis(...);
///   }
/// });
/// ```
class AutoCalibrationManager {
  /// Semaphores from SynthesisCoordinator for concurrency control.
  final Map<String, DynamicSemaphore> engineSemaphores;

  /// Callback to get current buffer ahead in ms.
  final BufferAheadCallback getBufferAheadMs;

  /// Callback to get current playback rate.
  final PlaybackRateCallback getPlaybackRate;

  /// Callback to check if playback is active.
  final IsPlayingCallback isPlaying;

  /// Interval for buffer gauge sampling.
  final Duration sampleInterval;

  /// Enable debug logging.
  final bool enableLogging;

  // Components
  BufferGauge? _bufferGauge;
  DemandController? _demandController;
  ConcurrencyGovernor? _concurrencyGovernor;
  RTFMonitor? _rtfMonitor;
  DeviceCapabilities? _deviceCapabilities;

  /// Creates an AutoCalibrationManager.
  AutoCalibrationManager({
    required this.engineSemaphores,
    required this.getBufferAheadMs,
    required this.getPlaybackRate,
    required this.isPlaying,
    this.sampleInterval = const Duration(seconds: 1),
    this.enableLogging = true,
  });

  /// Whether the manager has been initialized.
  bool get isInitialized => _bufferGauge != null;

  /// Whether the manager is actively monitoring.
  bool get isActive => _demandController?.isActive ?? false;

  /// Current demand level.
  DemandLevel? get currentDemandLevel => _demandController?.currentDemandLevel;

  /// Current concurrency level.
  int get currentConcurrency => _demandController?.currentConcurrency ?? 2;

  /// RTF statistics.
  RTFStatistics? get rtfStats => _rtfMonitor?.statistics;

  /// Device capabilities.
  DeviceCapabilities? get deviceCapabilities => _deviceCapabilities;

  /// Initialize the auto-calibration system.
  ///
  /// Must be called before [start].
  Future<void> initialize() async {
    if (isInitialized) {
      _log('Already initialized');
      return;
    }

    _log('Initializing auto-calibration...');

    // Detect device capabilities
    _deviceCapabilities = await DeviceCapabilities.detect();
    _log('Device: ${_deviceCapabilities!.estimatedTier.name}, '
        'maxConcurrency: ${_deviceCapabilities!.recommendedMaxConcurrency}');

    // Create RTF monitor
    _rtfMonitor = RTFMonitor(windowSize: 50);

    // Create buffer gauge
    _bufferGauge = BufferGauge(
      getBufferAheadMs: getBufferAheadMs,
      getPlaybackRate: getPlaybackRate,
      isPlaying: isPlaying,
      sampleInterval: sampleInterval,
    );

    // Create concurrency governor
    _concurrencyGovernor = ConcurrencyGovernor(
      engineSemaphores: engineSemaphores,
      enableLogging: enableLogging,
    );

    // Create demand controller
    _demandController = DemandController(
      bufferGauge: _bufferGauge!,
      onConcurrencyChange: _handleConcurrencyChange,
      baselineConcurrency: _deviceCapabilities!.suggestedBaselineConcurrency,
      maxConcurrency: _deviceCapabilities!.recommendedMaxConcurrency,
    );

    _log('Initialized: baseline=${_demandController!.baselineConcurrency}, '
        'max=${_demandController!.maxConcurrency}');
  }

  /// Start monitoring and auto-adjusting concurrency.
  void start() {
    if (!isInitialized) {
      _log('ERROR: Must call initialize() before start()');
      return;
    }

    _log('Starting auto-calibration monitoring');
    _demandController!.start();
  }

  /// Stop monitoring.
  void stop() {
    _log('Stopping auto-calibration monitoring');
    _demandController?.stop();
  }

  /// Record a synthesis completion for RTF tracking.
  ///
  /// Call this when a segment synthesis completes (not from cache).
  void recordSynthesis({
    required Duration audioDuration,
    required Duration synthesisTime,
    required String engineType,
    required String voiceId,
  }) {
    final concurrency = _concurrencyGovernor?.getConcurrency(engineType) ?? 1;

    _rtfMonitor?.recordSynthesis(
      audioDuration: audioDuration,
      synthesisTime: synthesisTime,
      concurrency: concurrency,
      engineType: engineType,
      voiceId: voiceId,
    );

    final rtf = synthesisTime.inMilliseconds / audioDuration.inMilliseconds;
    _log('RTF: ${rtf.toStringAsFixed(2)} ($engineType, '
        'audio=${audioDuration.inMilliseconds}ms, '
        'synth=${synthesisTime.inMilliseconds}ms, '
        'concurrency=$concurrency)');
  }

  /// Force a buffer sample (useful after seeks or state changes).
  void forceSample() {
    _bufferGauge?.forceSample();
  }

  /// Update baseline concurrency (from external learning).
  void updateBaseline(int newBaseline) {
    _demandController?.updateBaseline(newBaseline);
    _log('Baseline updated to $newBaseline');
  }

  /// Register a new semaphore (call when coordinator creates one).
  /// Forwards to ConcurrencyGovernor to apply current target concurrency.
  void registerSemaphore(String engineType, DynamicSemaphore semaphore) {
    _concurrencyGovernor?.registerSemaphore(engineType, semaphore);
  }

  /// Dispose of resources.
  void dispose() {
    _log('Disposing auto-calibration manager');
    stop();
    _bufferGauge?.dispose();
    _concurrencyGovernor?.dispose();
    _demandController?.dispose();
  }

  void _handleConcurrencyChange(int newConcurrency, DemandLevel reason) {
    _log('Concurrency change: $newConcurrency (reason: ${reason.name})');
    _concurrencyGovernor?.setConcurrency(newConcurrency, reason: reason);
  }

  void _log(String message) {
    if (enableLogging) {
      _logger.info(message);
    }
  }

  /// Get debug snapshot of current state.
  Map<String, dynamic> get debugSnapshot => {
        'isInitialized': isInitialized,
        'isActive': isActive,
        'currentDemandLevel': currentDemandLevel?.name,
        'currentConcurrency': currentConcurrency,
        'deviceTier': _deviceCapabilities?.estimatedTier.name,
        'maxConcurrency': _deviceCapabilities?.recommendedMaxConcurrency,
        'rtfSampleCount': _rtfMonitor?.sampleCount ?? 0,
        'rtfMean': rtfStats?.mean.toStringAsFixed(3),
        'rtfP95': rtfStats?.p95.toStringAsFixed(3),
        ...?_bufferGauge?.debugSnapshot,
      };
}
