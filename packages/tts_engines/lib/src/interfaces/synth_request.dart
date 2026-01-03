import 'dart:io';

/// Request parameters for TTS synthesis.
class SynthRequest {
  const SynthRequest({
    required this.voiceId,
    required this.text,
    required this.playbackRate,
    required this.outFile,
    this.tuning = const {},
  });

  /// Voice identifier (e.g., 'kokoro_af', 'supertonic_m1').
  final String voiceId;

  /// Text to synthesize.
  final String text;

  /// Playback rate (1.0 = normal speed).
  final double playbackRate;

  /// Output file path for the synthesized audio.
  final File outFile;

  /// Optional engine-specific tuning parameters.
  final Map<String, Object?> tuning;

  @override
  String toString() =>
      'SynthRequest(voice: $voiceId, textLen: ${text.length}, rate: $playbackRate)';
}
