/// Key for audio cache lookup.
///
/// Cache keys must be deterministic and stable across app restarts.
/// They include all parameters that affect synthesis output.
class CacheKey {
  const CacheKey({
    required this.voiceId,
    required this.textHash,
    required this.synthesisRate,
  });

  /// Voice identifier.
  final String voiceId;

  /// Stable hash of the normalized text.
  final String textHash;

  /// Synthesis rate (1.0 for rate-independent synthesis).
  final double synthesisRate;

  /// Generate filename for this cache key.
  String toFilename() {
    final rateStr = synthesisRate.toStringAsFixed(2).replaceAll('.', '_');
    return '${voiceId}_${rateStr}_$textHash.wav';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheKey &&
          runtimeType == other.runtimeType &&
          voiceId == other.voiceId &&
          textHash == other.textHash &&
          synthesisRate == other.synthesisRate;

  @override
  int get hashCode => Object.hash(voiceId, textHash, synthesisRate);

  @override
  String toString() =>
      'CacheKey(voice: $voiceId, hash: $textHash, rate: $synthesisRate)';
}
