import 'package:core_domain/core_domain.dart';

import 'segment_synth_request.dart';
import 'synth_request.dart';
import 'synth_result.dart';
import 'tts_state_machines.dart';

/// Availability status for a TTS engine.
enum EngineAvailability {
  /// Engine is ready to use.
  available,

  /// Engine requires core model download.
  needsCore,

  /// Engine requires voice assets download.
  needsVoice,

  /// Engine is not supported on this platform.
  unsupported,

  /// Engine encountered an error during probe.
  error,
}

/// Core variant selector for engines with multiple model options.
class CoreSelector {
  const CoreSelector({
    required this.variant,
    this.preferInt8 = true,
  });

  /// Core variant identifier (e.g., 'fp32', 'int8').
  final String variant;

  /// Whether to prefer INT8 quantized models when available.
  final bool preferInt8;

  static const defaultKokoro = CoreSelector(variant: 'int8', preferInt8: true);
  static const defaultSupertonic = CoreSelector(variant: 'default');
  static const defaultPiper = CoreSelector(variant: 'default');
}

/// Abstract interface for AI voice engines.
///
/// Each engine implementation (Piper, Supertonic, Kokoro) implements this
/// interface to provide a consistent synthesis API.
abstract interface class AiVoiceEngine {
  /// Unique identifier for this engine.
  EngineType get engineType;

  /// Probe whether the engine is available and ready.
  Future<EngineAvailability> probe();

  /// Ensure required core assets are installed.
  ///
  /// This may trigger downloads or extraction if assets are missing.
  Future<void> ensureCoreReady(CoreSelector selector);

  /// Get current core readiness state with progress.
  Future<CoreReadiness> getCoreReadiness(String voiceId);

  /// Watch core readiness changes (for UI progress).
  Stream<CoreReadiness> watchCoreReadiness(String coreId);

  /// Check voice readiness with state machine.
  Future<VoiceReadiness> checkVoiceReady(String voiceId);

  /// Synthesize text to a WAV file.
  ///
  /// [request] contains all synthesis parameters including voice ID,
  /// text, playback rate, and output file path.
  ///
  /// Returns a [SynthResult] with the output file and duration.
  /// The caller is responsible for providing a valid output file path.
  Future<SynthResult> synthesizeToFile(SynthRequest request);

  /// Synthesize a segment with full lifecycle tracking.
  Future<ExtendedSynthResult> synthesizeSegment(SegmentSynthRequest request);

  /// Warm up the engine for a specific voice.
  ///
  /// This pre-initializes the engine and loads the voice model so that
  /// the first synthesis request doesn't experience startup latency.
  /// Should be called when the playback screen opens, before the user presses play.
  ///
  /// Returns true if warm-up was successful, false if the voice is not available.
  Future<bool> warmUp(String voiceId);

  /// Cancel an in-flight synthesis operation.
  Future<void> cancelSynth(String requestId);

  /// Check if a specific voice is ready for synthesis.
  Future<bool> isVoiceReady(String voiceId);

  /// Get number of models currently loaded.
  Future<int> getLoadedModelCount();

  /// Unload the least-recently-used model to free memory.
  Future<void> unloadLeastUsedModel();

  /// Clear all loaded models.
  Future<void> clearAllModels();

  /// Dispose of any resources held by this engine.
  Future<void> dispose();
}

/// Exception thrown when voice synthesis fails.
class SynthesisException implements Exception {
  const SynthesisException(this.message, {this.voiceId, this.cause});

  final String message;
  final String? voiceId;
  final Object? cause;

  @override
  String toString() {
    var result = 'SynthesisException: $message';
    if (voiceId != null) result += ' (voice: $voiceId)';
    if (cause != null) result += '\nCause: $cause';
    return result;
  }
}

/// Exception thrown when a voice is not available.
class VoiceNotAvailableException implements Exception {
  const VoiceNotAvailableException(this.voiceId, this.message);

  final String voiceId;
  final String message;

  @override
  String toString() => 'VoiceNotAvailableException: $message (voice: $voiceId)';
}
