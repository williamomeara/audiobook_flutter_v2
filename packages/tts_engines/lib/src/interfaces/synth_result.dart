import 'dart:io';

/// Result of a TTS synthesis operation.
class SynthResult {
  const SynthResult({
    required this.file,
    required this.durationMs,
    this.sampleRate = 24000,
  });

  /// The synthesized audio file (WAV format).
  final File file;

  /// Duration of the audio in milliseconds.
  final int durationMs;

  /// Sample rate of the audio (default 24kHz for neural TTS).
  final int sampleRate;

  @override
  String toString() =>
      'SynthResult(path: ${file.path}, durationMs: $durationMs)';
}
