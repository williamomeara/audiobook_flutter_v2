import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playback/playback.dart';

import 'config/config_providers.dart';
import 'playback_providers.dart';
import 'tts_providers.dart';

/// Provider for the engine calibration service.
///
/// Use this to calibrate TTS engines and find optimal concurrency.
final engineCalibrationServiceProvider = Provider<EngineCalibrationService>((ref) {
  return EngineCalibrationService();
});

/// Provider to check if an engine needs calibration.
///
/// Returns true if the engine has never been calibrated on this device.
final engineNeedsCalibrationProvider = Provider.family<bool, String>((ref, engineType) {
  final config = ref.watch(runtimePlaybackConfigProvider).value;
  if (config == null) return true; // Default to needing calibration
  return !config.isEngineCalibrated(engineType);
});

/// Provider to get optimal concurrency for an engine.
///
/// Uses calibrated value if available, otherwise falls back to defaults.
final optimalConcurrencyProvider = Provider.family<int, String>((ref, engineType) {
  final config = ref.watch(runtimePlaybackConfigProvider).value;
  if (config == null) return 2; // Safe default
  return config.getOptimalConcurrency(engineType);
});

/// Provider to get calibration speedup for an engine.
///
/// Returns null if not calibrated.
final calibrationSpeedupProvider = Provider.family<double?, String>((ref, engineType) {
  final config = ref.watch(runtimePlaybackConfigProvider).value;
  return config?.getCalibrationSpeedup(engineType);
});

/// State class for calibration notifier.
class CalibrationState {
  const CalibrationState({
    this.isCalibrating = false,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.message = '',
    this.lastResult,
    this.error,
  });

  final bool isCalibrating;
  final int currentStep;
  final int totalSteps;
  final String message;
  final CalibrationResult? lastResult;
  final String? error;

  CalibrationState copyWith({
    bool? isCalibrating,
    int? currentStep,
    int? totalSteps,
    String? message,
    CalibrationResult? lastResult,
    String? error,
  }) {
    return CalibrationState(
      isCalibrating: isCalibrating ?? this.isCalibrating,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      message: message ?? this.message,
      lastResult: lastResult ?? this.lastResult,
      error: error,
    );
  }
}

/// Notifier for managing calibration state and actions.
class CalibrationNotifier extends Notifier<CalibrationState> {
  @override
  CalibrationState build() {
    return const CalibrationState();
  }

  /// Run calibration for a specific voice.
  ///
  /// Automatically saves the result to RuntimePlaybackConfig.
  Future<CalibrationResult?> calibrate({
    required String voiceId,
    required String engineType,
  }) async {
    if (state.isCalibrating) {
      developer.log(
        '[Calibration] Already calibrating, ignoring request',
        name: 'CalibrationNotifier',
      );
      return null;
    }

    state = const CalibrationState(
      isCalibrating: true,
      message: 'Preparing calibration...',
    );

    try {
      final service = ref.read(engineCalibrationServiceProvider);
      final routingEngine = await ref.read(ttsRoutingEngineProvider.future);
      final cacheManager = await ref.read(intelligentCacheManagerProvider.future);

      final result = await service.calibrateEngine(
        routingEngine: routingEngine,
        voiceId: voiceId,
        onProgress: (step, total, message) {
          state = state.copyWith(
            currentStep: step,
            totalSteps: total,
            message: message,
          );
        },
        clearCacheFunc: () => cacheManager.clear(),
      );

      // Save calibration result
      await ref.read(runtimePlaybackConfigProvider.notifier).saveCalibration(
        engineType: engineType,
        optimalConcurrency: result.optimalConcurrency,
        speedup: result.expectedSpeedup,
        rtf: result.rtfAtOptimal,
      );

      state = CalibrationState(
        isCalibrating: false,
        lastResult: result,
        message: 'Calibration complete',
      );

      developer.log(
        '[Calibration] Complete for $engineType: $result',
        name: 'CalibrationNotifier',
      );

      return result;
    } catch (e, st) {
      developer.log(
        '[Calibration] Failed: $e',
        name: 'CalibrationNotifier',
        error: e,
        stackTrace: st,
      );

      state = CalibrationState(
        isCalibrating: false,
        error: e.toString(),
        message: 'Calibration failed',
      );

      return null;
    }
  }

  /// Reset calibration state.
  void reset() {
    state = const CalibrationState();
  }
}

/// Provider for calibration state and actions.
final calibrationProvider = NotifierProvider<CalibrationNotifier, CalibrationState>(
  CalibrationNotifier.new,
);
