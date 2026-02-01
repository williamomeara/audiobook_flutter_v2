import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'voice_warmup_state.dart';

/// Callback signature for engine initialization.
/// Returns true if initialization succeeded.
typedef EngineInitCallback = Future<void> Function(String corePath);

/// Callback signature for voice loading.
/// Returns true if loading succeeded.
typedef VoiceLoadCallback = Future<void> Function(String voiceId, String modelPath);

/// Controller for managing progressive voice warmup.
///
/// This controller manages the warmup state machine for TTS voice engines,
/// providing observable state changes for UI feedback during the potentially
/// slow CoreML compilation on iOS.
///
/// Key features:
/// - Progressive phase tracking (file validation → engine init → voice loading)
/// - Serialized warmup calls (prevents duplicate concurrent compilations)
/// - Observable state via streams for reactive UI
/// - Cancellation support
/// - Graceful error handling
class VoiceWarmupController {
  VoiceWarmupController({
    required this.engineId,
    required this.coreDir,
    required this.onInitEngine,
    required this.onLoadVoice,
    this.getCorePathForVoice,
    this.getModelPathForVoice,
    this.isEngineReady,
    this.isVoiceLoaded,
  });

  /// Engine identifier (e.g., 'supertonic', 'kokoro').
  final String engineId;

  /// Base directory for voice assets.
  final Directory coreDir;

  /// Callback to initialize the engine.
  final EngineInitCallback onInitEngine;

  /// Callback to load a voice.
  final VoiceLoadCallback onLoadVoice;

  /// Optional function to get core path for a voice.
  final String Function(String voiceId)? getCorePathForVoice;

  /// Optional function to get model path for a voice.
  final String Function(String voiceId)? getModelPathForVoice;

  /// Optional function to check if engine is already initialized.
  final bool Function()? isEngineReady;

  /// Optional function to check if a voice is already loaded.
  final bool Function(String voiceId)? isVoiceLoaded;

  /// Active warmup states per voice.
  final Map<String, VoiceWarmupState> _states = {};

  /// Stream controllers for warmup state changes.
  final Map<String, StreamController<VoiceWarmupState>> _controllers = {};

  /// Completer for serializing warmup calls per voice.
  final Map<String, Completer<bool>> _warmupCompleters = {};

  /// Cancelled voice IDs.
  final Set<String> _cancelled = {};

  /// Get current warmup state for a voice.
  VoiceWarmupState getState(String voiceId) {
    return _states[voiceId] ?? VoiceWarmupState.initial(voiceId);
  }

  /// Watch warmup state changes for a voice.
  Stream<VoiceWarmupState> watchState(String voiceId) {
    _controllers[voiceId] ??= StreamController<VoiceWarmupState>.broadcast();
    return _controllers[voiceId]!.stream;
  }

  /// Start warming up a voice.
  ///
  /// Returns true if warmup succeeded, false if it failed or was cancelled.
  /// If another warmup is in progress for this voice, waits for it instead
  /// of starting a new one.
  Future<bool> warmUp(String voiceId) async {
    // Check if already warming up - wait for existing warmup
    if (_warmupCompleters.containsKey(voiceId)) {
      debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) waiting for existing warmup...');
      try {
        return await _warmupCompleters[voiceId]!.future;
      } catch (e) {
        debugPrint('[VoiceWarmupController] $engineId: existing warmup failed, retrying...');
        // Previous warmup failed, continue to try again
      }
    }

    // Check if already ready (both cached warmup state AND actual engine state)
    final currentState = getState(voiceId);
    if (currentState.isReady) {
      // Verify engine is actually still ready (not unloaded by memory manager)
      final engineReady = isEngineReady?.call() ?? false;
      final voiceLoaded = isVoiceLoaded?.call(voiceId) ?? false;
      if (engineReady && voiceLoaded) {
        debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) already ready (verified)');
        return true;
      }
      // Engine was unloaded by memory manager, reset cached state and proceed with warmup
      debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) state shows ready but engine unloaded, re-warming');
    }

    // Start new warmup
    _warmupCompleters[voiceId] = Completer<bool>();
    _cancelled.remove(voiceId);

    final startTime = DateTime.now();
    debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) starting...');

    try {
      // Phase 1: File validation
      _updateState(voiceId, VoiceWarmupState(
        voiceId: voiceId,
        phase: WarmupPhase.fileValidation,
        startTime: startTime,
        phaseStartTime: DateTime.now(),
      ));

      final corePath = getCorePathForVoice?.call(voiceId) ??
          _defaultCorePath(voiceId);
      final corePathDir = Directory(corePath);

      if (!await corePathDir.exists()) {
        throw WarmupException(
          'Core files not found at $corePath',
          phase: WarmupPhase.fileValidation,
        );
      }

      if (_isCancelled(voiceId)) {
        throw WarmupCancelledException(voiceId);
      }

      // Phase 2: Engine initialization (the slow part on iOS)
      final needsInit = !(isEngineReady?.call() ?? false);
      if (needsInit) {
        _updateState(voiceId, VoiceWarmupState(
          voiceId: voiceId,
          phase: WarmupPhase.coreInitializing,
          message: Platform.isIOS
              ? 'Preparing voice engine (one-time setup)...'
              : 'Initializing engine...',
          startTime: startTime,
          phaseStartTime: DateTime.now(),
        ));

        debugPrint('[VoiceWarmupController] $engineId: initializing engine at $corePath...');
        await onInitEngine(corePath);
        debugPrint('[VoiceWarmupController] $engineId: engine initialized');
      }

      if (_isCancelled(voiceId)) {
        throw WarmupCancelledException(voiceId);
      }

      // Phase 3: Voice loading
      final needsLoad = !(isVoiceLoaded?.call(voiceId) ?? false);
      if (needsLoad) {
        _updateState(voiceId, VoiceWarmupState(
          voiceId: voiceId,
          phase: WarmupPhase.voiceLoading,
          startTime: startTime,
          phaseStartTime: DateTime.now(),
        ));

        final modelPath = getModelPathForVoice?.call(voiceId) ??
            _defaultModelPath(voiceId, corePath);

        debugPrint('[VoiceWarmupController] $engineId: loading voice $voiceId...');
        await onLoadVoice(voiceId, modelPath);
        debugPrint('[VoiceWarmupController] $engineId: voice loaded');
      }

      // Complete
      final finalState = VoiceWarmupState.ready(voiceId, startTime);
      _updateState(voiceId, finalState);

      final duration = DateTime.now().difference(startTime);
      debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) complete in ${duration.inMilliseconds}ms');

      _warmupCompleters[voiceId]?.complete(true);
      return true;
    } on WarmupCancelledException {
      debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) cancelled');
      _updateState(voiceId, VoiceWarmupState(
        voiceId: voiceId,
        phase: WarmupPhase.notStarted,
        startTime: startTime,
      ));
      _warmupCompleters[voiceId]?.complete(false);
      return false;
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('[VoiceWarmupController] $engineId: warmUp($voiceId) failed after ${duration.inMilliseconds}ms: $e');

      _updateState(voiceId, VoiceWarmupState.failed(voiceId, e.toString(), startTime));
      _warmupCompleters[voiceId]?.completeError(e);
      return false;
    } finally {
      _warmupCompleters.remove(voiceId);
    }
  }

  /// Cancel warmup for a voice.
  void cancel(String voiceId) {
    _cancelled.add(voiceId);
  }

  /// Check if warmup is in progress for a voice.
  bool isWarmingUp(String voiceId) {
    return _warmupCompleters.containsKey(voiceId);
  }

  /// Clear all state (useful for testing or reset).
  void reset() {
    _states.clear();
    _cancelled.clear();
    for (final completer in _warmupCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _warmupCompleters.clear();
  }

  /// Dispose all resources.
  void dispose() {
    reset();
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }

  // Private helpers

  void _updateState(String voiceId, VoiceWarmupState state) {
    _states[voiceId] = state;
    _controllers[voiceId]?.add(state);
  }

  bool _isCancelled(String voiceId) => _cancelled.contains(voiceId);

  String _defaultCorePath(String voiceId) {
    // Default implementation - subclasses can override via getCorePathForVoice
    return '${coreDir.path}/$engineId';
  }

  String _defaultModelPath(String voiceId, String corePath) {
    // Default implementation - subclasses can override via getModelPathForVoice
    return Platform.isIOS ? corePath : '$corePath/model.onnx';
  }
}

/// Exception thrown when warmup fails.
class WarmupException implements Exception {
  const WarmupException(this.message, {this.phase});

  final String message;
  final WarmupPhase? phase;

  @override
  String toString() => 'WarmupException: $message (phase: $phase)';
}

/// Exception thrown when warmup is cancelled.
class WarmupCancelledException implements Exception {
  const WarmupCancelledException(this.voiceId);

  final String voiceId;

  @override
  String toString() => 'WarmupCancelledException: $voiceId';
}
